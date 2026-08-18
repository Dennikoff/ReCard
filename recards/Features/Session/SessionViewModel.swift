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
    private(set) var blocks: [[ReCard]] = []
    private(set) var blockIndex = 0
    private(set) var queue: [ReCard] = []
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
            blocks = Self.arrange(cards, blockSize: blockSize, limit: limit)

        case .learn:
            let words = SessionService.newWords(in: context, deck: deck)
            let limit = SessionService.remainingNewWords(in: context) + additionalNewWords
            let selected = Array(words.prefix(limit))
            // Новые слова показываются по одному, карточки создаются по ходу.
            blocks = selected.isEmpty ? [] : Self.chunk(selected, size: blockSize)
                .map { chunk in chunk.compactMap { word -> ReCard? in
                    word.ensureCards()
                    return word.card(for: .production)
                } }
        }

        startBlock()
    }

    /// Раскладывает карточки по блокам через общий алгоритм.
    private static func arrange(_ cards: [ReCard], blockSize: Int, limit: Int) -> [[ReCard]] {
        let byID = Dictionary(uniqueKeysWithValues: cards.map { ($0.id, $0) })
        let items = cards.compactMap { card -> SessionItem? in
            guard let wordID = card.word?.id else { return nil }
            return SessionItem(cardID: card.id, wordID: wordID, direction: card.direction)
        }

        return SessionBuilder
            .buildBlocks(from: items, blockSize: blockSize, limit: limit)
            .map { block in block.compactMap { byID[$0.cardID] } }
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
        guard let card = currentCard else {
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

        if card.direction == .recognition, let word = card.word {
            let correct = word.translations.first ?? ""
            options = (SessionService.distractors(for: word, in: context) + [correct]).shuffled()
        }

        stage = .asking
    }

    private func finishBlock() {
        // После знакомства с новыми словами блок повторяется как проверка печатью.
        if mode == .learn, !isCheckingNewWords, !pendingCheck.isEmpty {
            isCheckingNewWords = true
            queue = pendingCheck.compactMap { $0.card(for: .production) }
            pendingCheck = []
            presentCurrent()
            return
        }

        blockIndex += 1
        stage = blockIndex < blocks.count ? .blockBreak : .finished
    }

    var currentCard: ReCard? { queue.first }
    var currentWord: Word? { currentCard?.word }

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
        isCheckingNewWords = true
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
        guard let card = currentCard, let word = currentWord else { return }
        let verdict = AnswerChecker.check(input: typedAnswer, against: [word.text])
        lastInput = typedAnswer
        apply(verdict, to: card, word: word)
    }

    /// Выбор варианта в режиме узнавания.
    func selectOption(_ option: String) {
        guard let card = currentCard, let word = currentWord else { return }
        let verdict = AnswerChecker.check(input: option, against: word.translations)
        lastInput = option
        apply(verdict, to: card, word: word)
    }

    private func apply(_ verdict: AnswerVerdict, to card: ReCard, word: Word) {
        let elapsed = Date().timeIntervalSince(questionShownAt)
        let grade = FSRSScheduler.grade(for: verdict, responseTime: elapsed)

        record(grade: grade, verdict: verdict, card: card, word: word, elapsed: elapsed)

        if verdict == .incorrect {
            incorrectCount += 1
            mistakes.append(
                SessionMistake(
                    word: word.text,
                    expected: card.direction == .production
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

    /// Записывает результат в базу немедленно после каждой карточки.
    private func record(
        grade: ReRating,
        verdict: AnswerVerdict,
        card: ReCard,
        word: Word,
        elapsed: TimeInterval
    ) {
        let stateBefore = card.state

        if word.startedAt == nil {
            word.startedAt = Date()
        }

        if let result = try? scheduler.schedule(state: card.scheduleState, grade: grade, now: Date()) {
            card.apply(result)
        }

        context.insert(
            ReLog(
                cardID: card.id,
                wordID: word.id,
                grade: grade,
                state: stateBefore,
                direction: card.direction,
                elapsedDays: card.elapsedDays,
                scheduledDays: card.scheduledDays,
                responseTimeMS: Int(elapsed * 1000)
            )
        )

        try? context.save()
    }

    /// Пользователь настаивает, что ответ верен: оценка пересчитывается,
    /// а его вариант добавляется в список принимаемых переводов.
    func markLastAnswerCorrect() {
        guard case .answered(.incorrect) = stage,
              let card = currentCard,
              let word = currentWord else { return }

        if card.direction == .recognition {
            let normalized = AnswerChecker.normalize(lastInput)
            let isKnown = word.translations.contains { AnswerChecker.normalize($0) == normalized }
            if !isKnown, !lastInput.isEmpty {
                word.translations.append(lastInput)
            }
        }

        incorrectCount -= 1
        correctCount += 1
        mistakes.removeLast()

        if let result = try? scheduler.schedule(state: card.scheduleState, grade: .good, now: Date()) {
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

        let card = queue.removeFirst()
        if requeue {
            queue.append(card)
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
