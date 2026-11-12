import Foundation
import SwiftData
import Observation

/// Режим сессии.
enum SessionMode {
    /// Повторение созревших карточек.
    case review
    /// Знакомство с новыми словами и мини-проверка в конце блока.
    case learn
}

/// Что происходит на экране прямо сейчас.
enum SessionStage: Equatable {
    /// Показ новой карточки с кнопками «Знаю» / «Не знаю».
    case introducing
    /// Раскрытая новая карточка, которую пользователь просто читает.
    case reading
    /// Ожидание ответа.
    case asking
    /// Ответ дан, показан разбор.
    case answered(AnswerVerdict)
    /// Передышка между блоками.
    case blockBreak
    case finished
}

/// Одно упражнение в очереди: карточка слова и способ проверки.
struct SessionExercise: Identifiable {
    let id: UUID
    let card: ReCard
    let direction: CardDirection
    /// Повторная попытка после ошибки: в первичную оценку слова она не входит.
    var isRetry = false

    init(card: ReCard, direction: CardDirection, id: UUID = UUID()) {
        self.id = id
        self.card = card
        self.direction = direction
    }
}

/// Одна запись в итогах сессии.
struct SessionMistake: Identifiable {
    let id = UUID()
    var word: String
    var expected: String
    var given: String
    var language: String
}

/// Состояние и логика одной сессии.
///
/// Результат каждого ответа пишется в базу немедленно: понятия «незавершённая сессия»
/// не существует, выйти можно в любой момент без потерь.
@MainActor
@Observable
final class SessionViewModel {

    // MARK: - Состояние

    private(set) var stage: SessionStage = .asking
    private(set) var blocks: [[SessionExercise]] = []
    private(set) var blockIndex = 0
    private(set) var queue: [SessionExercise] = []
    private(set) var answeredInBlock = 0

    private(set) var correctCount = 0
    private(set) var incorrectCount = 0
    private(set) var mistakes: [SessionMistake] = []

    /// Варианты для режима выбора, пересобираются на каждой карточке.
    private(set) var options: [String] = []
    private(set) var lastInput = ""

    var typedAnswer = ""

    let mode: SessionMode

    private let context: ModelContext

    /// Контекст нужен экрану итогов, чтобы перестроить расписание напоминаний.
    var modelContext: ModelContext { context }
    private let scheduler: any Scheduler
    private var questionShownAt = Date()

    /// Новые слова, ожидающие мини-проверки в конце блока.
    private var pendingCheck: [Word] = []
    private var isCheckingNewWords = false
    /// Нормализованные тексты слов по колодам — чтобы не прощать как опечатку
    /// ввод другого слова колоды. Строится один раз на колоду за сессию.
    private var knownWordsByDeck: [UUID: Set<String>] = [:]
    /// Идёт подтверждение «Знаю» печатью. Отдельный флаг, а не `isCheckingNewWords`:
    /// подтверждение касается одного слова и не должно переводить блок в режим проверки.
    private var isConfirmingKnown = false

    /// Первичная оценка слова в повторении: состояние карточки до сессии и оценки
    /// за первую попытку каждого упражнения. Ключ — идентификатор карточки.
    private struct WordRound {
        var stateBefore: CardScheduleState
        var wasArchived: Bool
        var grades: [CardDirection: ReRating] = [:]

        /// Ошибка в любом упражнении — ошибка для всего слова.
        var worstGrade: ReRating? {
            grades.values.min { $0.rawValue < $1.rawValue }
        }
    }
    private var rounds: [UUID: WordRound] = [:]

    // MARK: - Инициализация

    /// - Parameter additionalNewWords: разрешение взять слова сверх дневной нормы.
    ///   Используется кнопкой «взять ещё» на главном экране, когда норма уже выполнена.
    init(
        mode: SessionMode,
        context: ModelContext,
        deck: Deck? = nil,
        additionalNewWords: Int = 0,
        scheduler: any Scheduler = FSRSScheduler()
    ) {
        self.mode = mode
        self.context = context
        self.scheduler = scheduler
        build(deck: deck, additionalNewWords: additionalNewWords)
    }

    private func build(deck: Deck?, additionalNewWords: Int) {
        let blockSize = AppSettings.blockSize

        switch mode {
        case .review:
            let cards = SessionService.dueCards(in: context, deck: deck)
            let limit = SessionService.remainingReviews(in: context)
            blocks = Self.arrange(
                cards,
                directions: SessionService.reviewDirections,
                blockSize: blockSize,
                limit: limit
            )

        case .learn:
            let words = SessionService.newWords(in: context, deck: deck)
            let limit = SessionService.remainingNewWords(in: context) + additionalNewWords
            let selected = Array(words.prefix(limit))
            // Новые слова показываются по одному, карточки создаются по ходу.
            blocks = selected.isEmpty ? [] : Self.chunk(selected, size: blockSize)
                .map { chunk in chunk.compactMap { word -> SessionExercise? in
                    word.ensureCard()
                    return word.card.map { SessionExercise(card: $0, direction: .production) }
                } }
        }

        startBlock()
    }

    /// Раскладывает карточки по блокам упражнений через общий алгоритм.
    private static func arrange(
        _ cards: [ReCard],
        directions: [CardDirection],
        blockSize: Int,
        limit: Int
    ) -> [[SessionExercise]] {
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let refs = cards.compactMap { card -> SessionCardRef? in
            guard let wordID = card.word?.id else { return nil }
            return SessionCardRef(cardID: card.id, wordID: wordID)
        }

        return SessionBuilder
            .buildBlocks(from: refs, directions: directions, blockSize: blockSize, limit: limit)
            .map { block in
                block.compactMap { item in
                    byID[item.cardID].map { SessionExercise(card: $0, direction: item.direction, id: item.id) }
                }
            }
    }

    private static func chunk<T>(_ items: [T], size: Int) -> [[T]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: items.count, by: size).map {
            Array(items[$0..<min($0 + size, items.count)])
        }
    }

    // MARK: - Ход сессии

    private func startBlock() {
        guard blockIndex < blocks.count else {
            stage = .finished
            return
        }
        queue = blocks[blockIndex]
        answeredInBlock = 0
        pendingCheck = []
        isCheckingNewWords = false
        presentCurrent()
    }

    private func presentCurrent() {
        guard let exercise = currentExercise else {
            finishBlock()
            return
        }

        typedAnswer = ""
        lastInput = ""
        questionShownAt = Date()
        options = []

        if mode == .learn, !isCheckingNewWords {
            stage = .introducing
            return
        }

        if exercise.direction == .recognition, let word = exercise.card.word {
            let correct = word.translations.first ?? ""
            options = (SessionService.distractors(for: word, in: context) + [correct]).shuffled()
        }

        stage = .asking
    }

    private func finishBlock() {
        // После знакомства с новыми словами блок повторяется как проверка печатью.
        if mode == .learn, !isCheckingNewWords, !pendingCheck.isEmpty {
            isCheckingNewWords = true
            queue = pendingCheck.compactMap { word in
                word.card.map { SessionExercise(card: $0, direction: .production) }
            }
            pendingCheck = []
            presentCurrent()
            return
        }

        blockIndex += 1
        stage = blockIndex < blocks.count ? .blockBreak : .finished
    }

    var currentExercise: SessionExercise? { queue.first }
    var currentCard: ReCard? { currentExercise?.card }
    var currentWord: Word? { currentCard?.word }
    /// Каким упражнением проверяется текущее слово.
    var currentDirection: CardDirection { currentExercise?.direction ?? .production }

    var progressText: String {
        guard blockIndex < blocks.count else { return "" }
        return "\(min(answeredInBlock + 1, blocks[blockIndex].count))/\(blocks[blockIndex].count)"
    }

    var progressValue: Double {
        guard blockIndex < blocks.count, !blocks[blockIndex].isEmpty else { return 0 }
        return Double(answeredInBlock) / Double(blocks[blockIndex].count)
    }

    var isLastBlock: Bool { blockIndex >= blocks.count - 1 }
    var totalAnswered: Int { correctCount + incorrectCount }

    // MARK: - Действия пользователя

    /// Пользователь заявил, что знает новое слово: приложение просит подтвердить печатью.
    func claimKnown() {
        isConfirmingKnown = true
        stage = .asking
        questionShownAt = Date()
    }

    /// Пользователь не знает слова — показывается разбор целиком.
    func revealNewWord() {
        stage = .reading
    }

    /// Переход к следующему слову после знакомства.
    func continueAfterReading() {
        if let word = currentWord {
            pendingCheck.append(word)
        }
        advance(removingCurrent: true)
    }

    /// Проверка напечатанного ответа.
    func submitTypedAnswer() {
        guard let exercise = currentExercise, let word = currentWord else { return }
        let verdict = AnswerChecker.check(
            input: typedAnswer,
            against: [word.text],
            knownWords: knownWords(for: word)
        )
        lastInput = typedAnswer
        if isConfirmingKnown {
            confirmKnown(verdict, card: exercise.card, word: word)
        } else {
            apply(verdict, to: exercise, word: word)
        }
    }

    private func knownWords(for word: Word) -> Set<String> {
        guard let deck = word.deck else { return [] }
        if let cached = knownWordsByDeck[deck.id] { return cached }
        let set = AnswerChecker.knownWordSet((deck.words ?? []).map(\.text))
        knownWordsByDeck[deck.id] = set
        return set
    }

    /// Итог подтверждения «Знаю»: верный ответ сразу отправляет слово в выученные
    /// (обе карточки в архив), неверный — слово обрабатывается как «Не знаю».
    private func confirmKnown(_ verdict: AnswerVerdict, card: ReCard, word: Word) {
        isConfirmingKnown = false
        let elapsed = Date().timeIntervalSince(questionShownAt)

        guard verdict != .incorrect else {
            // Состояние карточки не меняется, но попытка всё равно попадает в журнал.
            context.insert(
                ReLog(
                    cardID: card.id,
                    wordID: word.id,
                    grade: .again,
                    state: card.state,
                    direction: .production,
                    elapsedDays: card.elapsedDays,
                    scheduledDays: card.scheduledDays,
                    responseTimeMS: Int(elapsed * 1000)
                )
            )
            try? context.save()
            stage = .reading
            return
        }

        let grade = FSRSScheduler.grade(for: verdict, responseTime: elapsed)
        record(
            grade: grade,
            exercise: SessionExercise(card: card, direction: .production),
            word: word,
            elapsed: elapsed
        )
        card.isArchived = true
        try? context.save()

        correctCount += 1
        stage = .answered(verdict)
    }

    /// Выбор варианта в режиме узнавания.
    func selectOption(_ option: String) {
        guard let exercise = currentExercise, let word = currentWord else { return }
        let verdict = AnswerChecker.check(input: option, against: SessionService.acceptedTranslations(for: word))
        lastInput = option
        apply(verdict, to: exercise, word: word)
    }

    private func apply(_ verdict: AnswerVerdict, to exercise: SessionExercise, word: Word) {
        let elapsed = Date().timeIntervalSince(questionShownAt)
        let grade = FSRSScheduler.grade(for: verdict, responseTime: elapsed)

        record(grade: grade, exercise: exercise, word: word, elapsed: elapsed)

        if verdict == .incorrect {
            incorrectCount += 1
            mistakes.append(
                SessionMistake(
                    word: word.text,
                    expected: exercise.direction == .production
                        ? word.text
                        : word.translations.joined(separator: ", "),
                    given: lastInput,
                    language: word.deck?.sourceLanguage ?? "en-US"
                )
            )
        } else {
            correctCount += 1
        }

        stage = .answered(verdict)
    }

    /// Записывает результат в базу немедленно после каждого ответа.
    private func record(
        grade: ReRating,
        exercise: SessionExercise,
        word: Word,
        elapsed: TimeInterval
    ) {
        let card = exercise.card
        var stateBefore = card.state

        if word.startedAt == nil {
            word.startedAt = AppClock.now
        }

        if usesWordRound(exercise) {
            var round = rounds[card.id]
                ?? WordRound(stateBefore: card.scheduleState, wasArchived: card.isArchived)
            round.grades[exercise.direction] = grade
            rounds[card.id] = round
            stateBefore = round.stateBefore.state
            reschedule(card, from: round)
        } else if let result = try? scheduler.schedule(state: card.scheduleState, grade: grade, now: AppClock.now) {
            card.apply(result)
        }

        context.insert(
            ReLog(
                cardID: card.id,
                wordID: word.id,
                grade: grade,
                state: stateBefore,
                direction: exercise.direction,
                elapsedDays: card.elapsedDays,
                scheduledDays: card.scheduledDays,
                responseTimeMS: Int(elapsed * 1000)
            )
        )

        try? context.save()
    }

    /// Первые попытки упражнений в повторении складываются в одну оценку слова.
    /// Повторные попытки после ошибки и мини-проверка новых слов работают как раньше:
    /// каждый ответ — отдельный шаг планировщика.
    private func usesWordRound(_ exercise: SessionExercise) -> Bool {
        mode == .review && !exercise.isRetry
    }

    /// Пересчитывает карточку от состояния до сессии по худшей оценке слова.
    ///
    /// Пересчёт от исходного состояния, а не поверх текущего, нужен для того, чтобы
    /// два упражнения дали один шаг планировщика: верная печать и ошибка в выборе
    /// дают ровно то же, что одна ошибка. Каждый ответ при этом сохраняется сразу.
    private func reschedule(_ card: ReCard, from round: WordRound) {
        guard let grade = round.worstGrade,
              let result = try? scheduler.schedule(state: round.stateBefore, grade: grade, now: AppClock.now)
        else { return }
        // Архивация от пересчёта к пересчёту может отмениться: сначала верный ответ
        // дотянул устойчивость до порога, потом ошибка в другом упражнении — нет.
        card.isArchived = round.wasArchived
        card.apply(result)
    }

    /// Пользователь настаивает, что ответ верен: оценка пересчитывается,
    /// а его вариант добавляется в список принимаемых переводов.
    func markLastAnswerCorrect() {
        guard case .answered(.incorrect) = stage,
              let exercise = currentExercise,
              let word = currentWord else { return }
        let card = exercise.card

        if exercise.direction == .recognition {
            let normalized = AnswerChecker.normalize(lastInput)
            let isKnown = word.translations.contains { AnswerChecker.normalize($0) == normalized }
            if !isKnown, !lastInput.isEmpty {
                word.translations.append(lastInput)
            }
        }

        incorrectCount -= 1
        correctCount += 1
        mistakes.removeLast()

        if usesWordRound(exercise), var round = rounds[card.id] {
            round.grades[exercise.direction] = .good
            rounds[card.id] = round
            reschedule(card, from: round)
        } else if let result = try? scheduler.schedule(state: card.scheduleState, grade: .good, now: AppClock.now) {
            card.apply(result)
        }
        try? context.save()

        stage = .answered(.correct)
    }

    /// Переход к следующей карточке после разбора.
    func advanceAfterFeedback() {
        guard case .answered(let verdict) = stage else { return }
        // Ошибочная карточка возвращается в конец текущего блока.
        advance(removingCurrent: true, requeue: verdict == .incorrect)
    }

    private func advance(removingCurrent: Bool, requeue: Bool = false) {
        guard removingCurrent, !queue.isEmpty else {
            presentCurrent()
            return
        }

        var exercise = queue.removeFirst()
        if requeue {
            exercise.isRetry = true
            queue.append(exercise)
        } else {
            answeredInBlock += 1
        }
        presentCurrent()
    }

    func startNextBlock() {
        startBlock()
    }

    // MARK: - Озвучивание

    func speakCurrentWord() {
        guard let word = currentWord else { return }
        SpeechService.shared.speak(word.text, language: word.deck?.sourceLanguage ?? "en-US")
    }

    func speak(_ text: String, language: String) {
        SpeechService.shared.speak(text, language: language)
    }
}
