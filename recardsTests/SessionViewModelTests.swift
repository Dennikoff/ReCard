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
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = container.mainContext

        deck = Deck(name: "Тест", sourceLanguage: "de-DE", targetLanguage: "ru-RU")
        context.insert(deck)

        for index in 0..<wordCount {
            let word = Word(text: "wort\(index)", translations: ["слово\(index)"])
            word.deck = deck
            context.insert(word)
            deck.words = (deck.words ?? []) + [word]
            word.ensureCards()

            if started {
                // Слово уже изучается, обе карточки просрочены.
                word.startedAt = Date().addingTimeInterval(-86_400)
                for card in word.cards ?? [] {
                    card.state = .review
                    card.due = Date().addingTimeInterval(-3600)
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
        let word = try #require(model.currentWord)
        let dueBefore = card.due

        answer(model, card: card, word: word, correct: true)

        #expect(model.correctCount == 1)
        #expect(model.incorrectCount == 0)
        #expect(card.due > dueBefore, "Срок следующего показа должен уехать вперёд")
        #expect(environment.logCount() == 1)
    }

    @Test("Неверный ответ возвращает карточку в конец блока")
    func incorrectAnswerRequeuesCard() throws {
        let environment = try TestEnvironment(wordCount: 3, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        let card = try #require(model.currentCard)
        let word = try #require(model.currentWord)

        model.typedAnswer = card.direction == .production ? "заведомо неверно" : ""
        if card.direction == .recognition {
            model.selectOption("заведомо неверно")
        } else {
            model.submitTypedAnswer()
        }

        #expect(model.incorrectCount == 1)
        #expect(model.mistakes.count == 1)

        model.advanceAfterFeedback()

        // Карточка не исчезла из сессии, а ждёт своей очереди в конце блока.
        #expect(model.currentCard?.id != card.id)
        #expect(model.queue.last?.id == card.id)
        #expect(model.queue.contains { $0.id == card.id })
        _ = word
    }

    @Test("Кнопка «засчитать как верный» переносит ответ в верные")
    func markingAnswerCorrectFlipsCounters() throws {
        let environment = try TestEnvironment(wordCount: 1, started: true)
        let model = SessionViewModel(mode: .review, context: environment.context, deck: environment.deck)

        let card = try #require(model.currentCard)
        answer(model, card: card, word: try #require(model.currentWord), correct: false)

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

        // Парные карточки одного слова разнесены по разным блокам, поэтому до
        // направления «слово → перевод» приходится дойти через границу блока.
        try advance(model, to: .recognition)

        let card = try #require(model.currentCard)
        #expect(card.direction == .recognition)
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

        let total = model.blocks.reduce(0) { $0 + $1.count }
        #expect(total == 2)
    }

    /// Доводит сессию до карточки нужного направления, отвечая верно по пути.
    private func advance(_ model: SessionViewModel, to direction: CardDirection) throws {
        for _ in 0..<20 {
            if case .blockBreak = model.stage {
                model.startNextBlock()
                continue
            }
            guard let card = model.currentCard else { break }
            if card.direction == direction { return }

            answer(model, card: card, word: try #require(model.currentWord), correct: true)
            model.advanceAfterFeedback()
        }
        Issue.record("Карточка направления \(direction) в сессии не встретилась")
    }

    /// Отвечает на текущую карточку заведомо верно или заведомо неверно.
    private func answer(_ model: SessionViewModel, card: ReCard, word: Word, correct: Bool) {
        switch card.direction {
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

    @Test("Подтверждённое печатью слово получает прогресс")
    func confirmedKnownWordAdvances() throws {
        let environment = try TestEnvironment(wordCount: 1)
        let model = SessionViewModel(mode: .learn, context: environment.context, deck: environment.deck)

        let word = try #require(model.currentWord)
        model.claimKnown()
        model.typedAnswer = word.text
        model.submitTypedAnswer()

        #expect(model.correctCount == 1)
        #expect(word.startedAt != nil, "Слово должно выйти из состояния «новое»")
        #expect(environment.logCount() == 1)
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
