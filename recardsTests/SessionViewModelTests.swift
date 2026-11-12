import Testing
import Foundation
import SwiftData
@testable import recards

/// Общая обвязка: хранилище в памяти и колода с заданным числом слов.
@MainActor
private struct TestEnvironment {
    let container: ModelContainer
    let context: ModelContext
    let deck: Deck

    init(wordCount: Int = 3, started: Bool = false) throws {
        let schema = Schema([Deck.self, Word.self, ReCard.self, ReLog.self])
        // Уникальное имя: иначе in-memory хранилища тестов делят backend.
        let configuration = ModelConfiguration(UUID().uuidString, schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext

        deck = Deck(name: "Тест", sourceLanguage: "de-DE", targetLanguage: "ru-RU")
        context.insert(deck)

        for index in 0..<wordCount {
            let word = Word(text: "wort\(index)", translations: ["слово\(index)"])
            word.deck = deck
            context.insert(word)
            deck.words = (deck.words ?? []) + [word]
            word.ensureCard()

            if started {
                // Слово уже изучается, карточка просрочена.
                word.startedAt = Date().addingTimeInterval(-86_400)
                if let card = word.card {
                    card.state = .review
                    card.due = Date().addingTimeInterval(-3600)
                    card.lastReview = Date().addingTimeInterval(-6 * 86_400)
                    card.scheduledDays = 5
                    card.stability = 5
                    card.difficulty = 5
                    card.reps = 1
                }
            }
        }
    }

    func logCount() -> Int {
        (try? context.fetchCount(FetchDescriptor<ReLog>())) ?? 0
    }
}

@Suite("Сессия повторения", .serialized)
@MainActor
struct ReviewSessionTests {

    init() {
        // Тесты делят один UserDefaults, поэтому лимиты задаются явно.
        UserDefaults.standard.set(50, forKey: SettingsKey.reviewsPerDay)
        UserDefaults.standard.set(5, forKey: SettingsKey.newWordsPerDay)
        UserDefaults.standard.set(20, forKey: SettingsKey.blockSize)
        UserDefaults.standard.set(true, forKey: SettingsKey.recognitionEnabled)
    }

    @Test("Созревшие карточки попадают в сессию")
    func dueCardsAreCollected() throws {
        let environment = try TestEnvironment(wordCount: 3, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        #expect(model.currentCard != nil)
        #expect(model.stage == .asking)
    }

    @Test("Верный ответ засчитывается и пишется в журнал")
    func correctAnswerIsRecorded() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        let card = try #require(model.currentCard)
        let dueBefore = card.due

        answer(model, correct: true)

        #expect(model.correctCount == 1)
        #expect(model.incorrectCount == 0)
        #expect(card.due > dueBefore, "Срок следующего показа должен уехать вперёд")
        #expect(environment.logCount() == 1)
    }

    @Test("Неверный ответ возвращает карточку в конец блока")
    func incorrectAnswerRequeuesCard() throws {
        let environment = try TestEnvironment(wordCount: 3, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        let exercise = try #require(model.currentExercise)
        answer(model, correct: false)

        #expect(model.incorrectCount == 1)
        #expect(model.mistakes.count == 1)

        model.advanceAfterFeedback()

        // Упражнение не исчезло из сессии, а ждёт своей очереди в конце блока.
        #expect(model.currentExercise?.id != exercise.id)
        #expect(model.queue.last?.id == exercise.id)
        #expect(model.queue.last?.isRetry == true)
    }

    @Test("Кнопка «засчитать как верный» переносит ответ в верные")
    func markingAnswerCorrectFlipsCounters() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        answer(model, correct: false)

        #expect(model.incorrectCount == 1)

        model.markLastAnswerCorrect()

        #expect(model.correctCount == 1)
        #expect(model.incorrectCount == 0)
        #expect(model.mistakes.isEmpty)
        #expect(model.stage == .answered(.correct))
    }

    @Test("Свой вариант перевода добавляется к принимаемым")
    func markingCorrectAddsTranslation() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        UserDefaults.standard.set(true, forKey: SettingsKey.recognitionEnabled)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        // Выбор перевода идёт в блоке после печати.
        try advance(model, to: .recognition)

        #expect(model.currentDirection == .recognition)
        let word = try #require(model.currentWord)
        let before = word.translations.count

        model.selectOption("синоним которого не было")
        model.markLastAnswerCorrect()

        #expect(word.translations.count == before + 1)
        #expect(word.translations.contains("синоним которого не было"))
    }

    @Test("Пустая сессия сразу завершается")
    func emptySessionFinishes() throws {
        let environment = try TestEnvironment(wordCount: 2, started: false)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        #expect(model.stage == .finished)
        #expect(model.currentCard == nil)
    }

    @Test("Дневной лимит ограничивает размер сессии")
    func dailyLimitCapsSession() throws {
        UserDefaults.standard.set(2, forKey: SettingsKey.reviewsPerDay)
        defer { UserDefaults.standard.set(50, forKey: SettingsKey.reviewsPerDay) }

        let environment = try TestEnvironment(wordCount: 10, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        let words = Set(model.blocks.flatMap { $0 }.compactMap { $0.card.word?.id })
        #expect(words.count == 2, "Лимит считается в словах, а не в упражнениях")
    }

    @Test("Пять слов — один блок из десяти упражнений")
    func wordsMakeOneBlock() throws {
        let environment = try TestEnvironment(wordCount: 5, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        #expect(model.blocks.count == 1)
        #expect(model.blocks.first?.count == 10)
        #expect(SessionService.summary(in: environment.context).dueNow == 5, "Счётчик считает слова")
    }

    @Test("Два верных ответа — один шаг планировщика")
    func bothCorrectIsOneStep() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)
        let card = try #require(model.currentCard)

        try answerAll(model, correct: [.production: true, .recognition: true])

        #expect(card.reps == 2, "Слово повторено один раз, а не два")
        #expect(card.lapses == 0)
        #expect(card.due > Date().addingTimeInterval(86_400))
        #expect(environment.logCount() == 2, "Журнал пишется на каждое упражнение")
        #expect(SessionService.reviewsDoneToday(in: environment.context) == 1)
    }

    @Test("Ошибка в выборе перевода — ошибка для всего слова")
    func recognitionMistakeFailsWord() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)
        let card = try #require(model.currentCard)

        try answerAll(model, correct: [.production: true, .recognition: false])

        #expect(card.lapses == 1, "Верная печать не спасает слово")
        #expect(card.state == .relearning)
    }

    @Test("«Засчитать как верный» возвращает слову верную оценку")
    func markingCorrectRestoresWordGrade() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)
        let card = try #require(model.currentCard)

        answer(model, correct: true)
        model.advanceAfterFeedback()
        answer(model, correct: false)
        model.markLastAnswerCorrect()

        #expect(card.lapses == 0)
        #expect(card.reps == 2)
    }

    @Test("Ввод другого слова колоды — ошибка, а не опечатка")
    func otherDeckWordIsNotATypo() throws {
        // В колоде wort0 и wort1 — отличие в одну букву, как у соседних форм глагола.
        let environment = try TestEnvironment(wordCount: 2, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)
        try advance(model, to: .production)

        let word = try #require(model.currentWord)
        let other = try #require(environment.deck.sortedWords.first { $0.id != word.id })
        model.typedAnswer = other.text
        model.submitTypedAnswer()

        #expect(model.stage == .answered(.incorrect))
    }

    @Test("В режиме выбора засчитывается перевод слова с тем же текстом")
    func twinTranslationIsAcceptedInRecognition() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        UserDefaults.standard.set(true, forKey: SettingsKey.recognitionEnabled)

        // Вторая форма с тем же написанием, как `will` для ich и для er/sie/es.
        let original = try #require(environment.deck.sortedWords.first)
        let twin = Word(text: original.text, translations: ["близнец"])
        twin.deck = environment.deck
        environment.context.insert(twin)
        environment.deck.words = (environment.deck.words ?? []) + [twin]
        try environment.context.save()

        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)
        try advance(model, to: .recognition)
        #expect(model.currentWord?.id == original.id)

        model.selectOption("близнец")

        #expect(model.stage == .answered(.correct))
    }

    /// Доводит сессию до упражнения нужного направления, отвечая верно по пути.
    private func advance(_ model: SessionViewModel, to direction: CardDirection) throws {
        for _ in 0..<20 {
            if case .blockBreak = model.stage {
                model.startNextBlock()
                continue
            }
            guard model.currentExercise != nil else { break }
            if model.currentDirection == direction { return }

            answer(model, correct: true)
            model.advanceAfterFeedback()
        }
        Issue.record("Упражнение направления \(direction) в сессии не встретилось")
    }

    /// Отвечает на все упражнения блока по первому разу, повторные попытки не трогает.
    private func answerAll(_ model: SessionViewModel, correct: [CardDirection: Bool]) throws {
        while let exercise = model.currentExercise, !exercise.isRetry {
            answer(model, correct: try #require(correct[exercise.direction]))
            model.advanceAfterFeedback()
        }
    }

    /// Отвечает на текущее упражнение заведомо верно или заведомо неверно.
    private func answer(_ model: SessionViewModel, correct: Bool) {
        guard let word = model.currentWord else { return }
        switch model.currentDirection {
        case .production:
            model.typedAnswer = correct ? word.text : "заведомо неверный ответ"
            model.submitTypedAnswer()
        case .recognition:
            model.selectOption(correct ? (word.translations.first ?? "") : "заведомо неверный ответ")
        }
    }
}

@Suite("Изучение новых слов", .serialized)
@MainActor
struct LearnSessionTests {

    init() {
        UserDefaults.standard.set(5, forKey: SettingsKey.newWordsPerDay)
        UserDefaults.standard.set(20, forKey: SettingsKey.blockSize)
    }

    @Test("Новое слово показывается с выбором «знаю» или «не знаю»")
    func newWordStartsWithChoice() throws {
        let environment = try TestEnvironment(wordCount: 2)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        #expect(model.stage == .introducing)
        #expect(model.currentWord != nil)
    }

    @Test("«Знаю» требует подтверждения печатью")
    func claimingKnownAsksToType() throws {
        let environment = try TestEnvironment(wordCount: 1)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        model.claimKnown()

        #expect(model.stage == .asking, "Приложение не должно верить на слово")
    }

    @Test("Подтверждённое печатью «Знаю» сразу отправляет слово в выученные")
    func confirmedKnownWordIsLearned() throws {
        let environment = try TestEnvironment(wordCount: 1)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        let word = try #require(model.currentWord)
        model.claimKnown()
        model.typedAnswer = word.text
        model.submitTypedAnswer()

        #expect(model.stage == .answered(.correct))
        #expect(model.correctCount == 1)
        #expect(word.startedAt != nil, "Слово должно выйти из состояния «новое»")
        #expect(word.isLearned, "Карточка слова должна уйти в архив")
        #expect(environment.logCount() == 1)
    }

    @Test("После «Знаю» следующее слово снова показывается с выбором")
    func knownWordDoesNotLeakIntoNextWord() throws {
        let environment = try TestEnvironment(wordCount: 2)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        let first = try #require(model.currentWord)
        model.claimKnown()
        model.typedAnswer = first.text
        model.submitTypedAnswer()
        model.advanceAfterFeedback()

        #expect(model.stage == .introducing)
        #expect(model.currentWord?.id != first.id)
    }

    @Test("Мини-проверка не пропускается, если в блоке было «Знаю»")
    func miniCheckSurvivesKnownWord() throws {
        let environment = try TestEnvironment(wordCount: 2)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        let first = try #require(model.currentWord)
        model.claimKnown()
        model.typedAnswer = first.text
        model.submitTypedAnswer()
        model.advanceAfterFeedback()

        let second = try #require(model.currentWord)
        model.revealNewWord()
        model.continueAfterReading()

        #expect(model.stage == .asking, "Должна начаться мини-проверка")
        #expect(model.currentWord?.id == second.id)
    }

    @Test("Неверное подтверждение «Знаю» обрабатывается как «Не знаю»")
    func failedKnownClaimFallsBackToReading() throws {
        let environment = try TestEnvironment(wordCount: 1)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        let word = try #require(model.currentWord)
        model.claimKnown()
        model.typedAnswer = "совсем не то"
        model.submitTypedAnswer()

        #expect(model.stage == .reading, "Карточка раскрывается целиком")
        #expect(!word.isLearned)
        #expect(word.startedAt == nil, "Слово остаётся новым до мини-проверки")
        #expect(environment.logCount() == 1, "Попытка всё равно пишется в журнал")

        model.continueAfterReading()
        #expect(model.stage == .asking, "Слово уходит на мини-проверку")
        #expect(model.currentWord?.id == word.id)
    }

    @Test("«Не знаю» раскрывает карточку, а затем слово идёт на проверку")
    func unknownWordIsCheckedLater() throws {
        let environment = try TestEnvironment(wordCount: 1)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        model.revealNewWord()
        #expect(model.stage == .reading)

        model.continueAfterReading()

        // Блок знакомства закончился — начинается мини-проверка тех же слов.
        #expect(model.stage == .asking)
        #expect(model.currentWord != nil)
    }

    @Test("Дневной лимит новых слов соблюдается")
    func newWordLimitIsRespected() throws {
        UserDefaults.standard.set(2, forKey: SettingsKey.newWordsPerDay)
        defer { UserDefaults.standard.set(5, forKey: SettingsKey.newWordsPerDay) }

        let environment = try TestEnvironment(wordCount: 10)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        let total = model.blocks.reduce(0) { $0 + $1.count }
        #expect(total == 2)
    }
}

@Suite("Отвлекающие варианты", .serialized)
@MainActor
struct DistractorTests {

    @Test("Правильный перевод не попадает в отвлекающие варианты")
    func distractorsExcludeCorrectAnswer() throws {
        let environment = try TestEnvironment(wordCount: 6)
        let word = try #require(environment.deck.sortedWords.first)

        let distractors = SessionService.distractors(for: word, in: environment.context)

        #expect(distractors.count == 3)
        for option in distractors {
            #expect(!word.translations.contains(option))
        }
    }

    @Test("Принимаются переводы всех слов колоды с тем же текстом")
    func acceptedTranslationsIncludeTwins() throws {
        let environment = try TestEnvironment(wordCount: 2)
        let word = try #require(environment.deck.sortedWords.first)
        let twin = Word(text: word.text.uppercased(), translations: ["близнец"])
        twin.deck = environment.deck
        environment.context.insert(twin)
        environment.deck.words = (environment.deck.words ?? []) + [twin]

        let accepted = SessionService.acceptedTranslations(for: word)

        #expect(accepted.contains("близнец"))
        #expect(word.translations.allSatisfy(accepted.contains))
        #expect(accepted.count == word.translations.count + 1, "Чужие слова не примешиваются")
    }

    @Test("К существительному подбираются существительные")
    func nounGetsNouns() throws {
        let environment = try TestEnvironment(wordCount: 0)
        let deck = environment.deck
        let word = addWord("der Hund", "собака", .noun, to: deck, in: environment.context)
        for (text, translation) in [("die Katze", "кошка"), ("das Haus", "дом"), ("der Tisch", "стол")] {
            addWord(text, translation, .noun, to: deck, in: environment.context)
        }
        for (text, translation) in [("gehen", "идти"), ("lesen", "читать"), ("trinken", "пить")] {
            addWord(text, translation, .verb, to: deck, in: environment.context)
        }

        for _ in 0..<10 {
            let distractors = SessionService.distractors(for: word, in: environment.context)
            #expect(Set(distractors) == ["кошка", "дом", "стол"])
        }
    }

    @Test("К форме глагола — формы с тем же лицом")
    func verbFormGetsSamePerson() throws {
        let environment = try TestEnvironment(wordCount: 0)
        let deck = environment.deck
        let word = addWord("willst", "хотеть (du)", .verb, to: deck, in: environment.context)
        for (text, translation) in [("gehst", "идти (du)"), ("liest", "читать (du)"), ("trinkst", "пить (du)"),
                                    ("geht", "идти (er/sie/es)"), ("lesen", "читать"), ("der Hund", "собака")] {
            addWord(text, translation, text == "der Hund" ? .noun : .verb, to: deck, in: environment.context)
        }

        let distractors = SessionService.distractors(for: word, in: environment.context)

        #expect(Set(distractors) == ["идти (du)", "читать (du)", "пить (du)"])
    }

    @Test("Своей части речи не хватает — варианты добираются из других")
    func fallsBackToOtherKinds() throws {
        let environment = try TestEnvironment(wordCount: 0)
        let deck = environment.deck
        let word = addWord("gut", "хороший", .adjective, to: deck, in: environment.context)
        addWord("schlecht", "плохой", .adjective, to: deck, in: environment.context)
        for (text, translation) in [("der Hund", "собака"), ("gehen", "идти"), ("das Haus", "дом")] {
            addWord(text, translation, text == "gehen" ? .verb : .noun, to: deck, in: environment.context)
        }

        for _ in 0..<10 {
            let distractors = SessionService.distractors(for: word, in: environment.context)
            #expect(distractors.count == 3)
            #expect(distractors.first == "плохой", "Своя часть речи идёт первой")
        }
    }

    @Test("Пометка лица извлекается из скобок в конце перевода")
    func personTagParsing() {
        #expect(SessionService.personTag(of: "хотеть (du)") == "du")
        #expect(SessionService.personTag(of: "быть (wir/sie/Sie)") == "wir/sie/sie")
        #expect(SessionService.personTag(of: "хотеть") == nil)
        #expect(SessionService.personTag(of: "(ну) и что") == nil)
        #expect(SessionService.personTag(of: nil) == nil)
    }

    @discardableResult
    private func addWord(
        _ text: String,
        _ translation: String,
        _ kind: PartOfSpeech,
        to deck: Deck,
        in context: ModelContext
    ) -> Word {
        let word = Word(text: text, translations: [translation], partOfSpeech: kind)
        word.deck = deck
        context.insert(word)
        deck.words = (deck.words ?? []) + [word]
        return word
    }

    @Test("В маленькой колоде вариантов меньше, но без падения")
    func smallDeckProducesFewerOptions() throws {
        let environment = try TestEnvironment(wordCount: 2)
        let word = try #require(environment.deck.sortedWords.first)

        let distractors = SessionService.distractors(for: word, in: environment.context)

        #expect(distractors.count == 1)
    }

    @Test("Варианты не повторяются")
    func distractorsAreUnique() throws {
        let environment = try TestEnvironment(wordCount: 8)
        let word = try #require(environment.deck.sortedWords.first)

        let distractors = SessionService.distractors(for: word, in: environment.context)

        #expect(Set(distractors).count == distractors.count)
    }
}
