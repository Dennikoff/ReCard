import Testing
import Foundation
import SwiftData
@testable import recards

/// Контейнер нужно удерживать: если его отпустить, `mainContext` становится
/// невалидным и первый же `insert` роняет процесс.
///
/// Каждому контейнеру задаётся уникальное имя конфигурации: иначе несколько
/// in-memory хранилищ с одинаковой схемой делят один backend, и данные одного
/// теста протекают в другой.
@MainActor
private func makeContainer() throws -> ModelContainer {
    let schema = Schema([Deck.self, Word.self, ReCard.self, ReLog.self])
    let configuration = ModelConfiguration(
        UUID().uuidString,
        schema: schema,
        isStoredInMemoryOnly: true
    )
    return try ModelContainer(for: schema, configurations: [configuration])
}

@MainActor
@discardableResult
private func makeDeck(in context: ModelContext, name: String = "Тест", started: Bool = false) -> Deck {
    let deck = Deck(name: name, sourceLanguage: "de-DE", targetLanguage: "ru-RU")
    context.insert(deck)

    for index in 0..<3 {
        let word = Word(
            text: "wort\(index)",
            translations: ["слово\(index)", "вариант\(index)"],
            transcription: "/w\(index)/",
            example: "Beispiel \(index).",
            exampleTranslation: "Пример \(index)."
        )
        // Разнесённые даты создания задают устойчивый порядок сортировки слов.
        word.createdAt = Date(timeIntervalSince1970: 1_700_000_000 + Double(index))
        word.deck = deck
        context.insert(word)
        deck.words = (deck.words ?? []) + [word]
        word.ensureCard()

        if started {
            word.startedAt = Date()
            if let card = word.card {
                card.state = .review
                card.stability = 12.5
                card.reps = 3
                card.due = Date().addingTimeInterval(86_400)
            }
        }
    }

    // Bulk-удаление (`delete(model:)`) работает только с сохранёнными объектами,
    // а в приложении данные всегда сохранены автосейвом. Воспроизводим это в тесте.
    try? context.save()
    return deck
}

@Suite("Резервное копирование", .serialized)
@MainActor
struct BackupServiceTests {

    @Test("Снимок содержит все колоды и слова")
    func backupCapturesEverything() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeDeck(in: context, name: "Первая")
        _ = makeDeck(in: context, name: "Вторая")

        let backup = BackupService.makeBackup(in: context)

        #expect(backup.decks.count == 2)
        #expect(backup.decks.allSatisfy { $0.words.count == 3 })
    }

    @Test("Восстановление воспроизводит данные без потерь")
    func restoreRoundTrip() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeDeck(in: context, name: "Немецкий", started: true)

        let data = try BackupService.encode(BackupService.makeBackup(in: context))

        // Другое хранилище имитирует переустановку приложения.
        let freshContainer = try makeContainer()
        let fresh = freshContainer.mainContext
        let backup = try BackupService.decode(data)
        try BackupService.restore(backup, into: fresh)

        let decks = try fresh.fetch(FetchDescriptor<Deck>())
        #expect(decks.count == 1)

        let deck = try #require(decks.first)
        #expect(deck.name == "Немецкий")
        #expect(deck.sortedWords.count == 3)

        let word = try #require(deck.sortedWords.first)
        #expect(word.translations.count == 2)
        #expect(word.startedAt != nil)
        #expect(word.transcription == "/w0/")
        #expect((word.cards ?? []).count == 1)

        let card = try #require(word.card)
        #expect(card.stability == 12.5)
        #expect(card.reps == 3)
        #expect(card.state == .review)
    }

    @Test("Восстановление заменяет, а не добавляет")
    func restoreReplacesExistingData() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeDeck(in: context, name: "Старая")
        let backup = BackupService.makeBackup(in: context)

        // Добавляем лишнюю колоду, которой в снимке нет.
        _ = makeDeck(in: context, name: "Лишняя")
        #expect(try context.fetchCount(FetchDescriptor<Deck>()) == 2)

        try BackupService.restore(backup, into: context)

        let decks = try context.fetch(FetchDescriptor<Deck>())
        #expect(decks.count == 1)
        #expect(decks.first?.name == "Старая")
    }

    @Test("Сброс прогресса сохраняет слова, но обнуляет карточки")
    func resetProgressKeepsWords() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeDeck(in: context, started: true)

        try BackupService.resetAllProgress(in: context)

        let words = try context.fetch(FetchDescriptor<Word>())
        #expect(words.count == 3)
        #expect(words.allSatisfy { $0.isNew })
        #expect(words.allSatisfy { ($0.cards ?? []).allSatisfy { !$0.isArchived && $0.state == .new } })
    }

    @Test("Полное удаление стирает все сущности")
    func deleteAllClearsEverything() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeDeck(in: context, started: true)

        try BackupService.deleteAll(in: context)

        #expect(try context.fetchCount(FetchDescriptor<Deck>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<Word>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<ReCard>()) == 0)
    }

    @Test("Копия из версии с двумя карточками восстанавливается с одной")
    func restoreDropsRecognitionCard() throws {
        let container = try makeContainer()
        let context = container.mainContext
        _ = makeDeck(in: context, started: true)
        var backup = BackupService.makeBackup(in: context)

        // Обратная карточка из старого формата, причём первой в списке.
        for wordIndex in backup.decks[0].words.indices {
            var old = backup.decks[0].words[wordIndex].cards[0]
            old.direction = CardDirection.recognition.rawValue
            old.stability = 99
            backup.decks[0].words[wordIndex].cards.insert(old, at: 0)
        }

        try BackupService.restore(backup, into: context)

        let words = try context.fetch(FetchDescriptor<Word>())
        #expect(words.allSatisfy { ($0.cards ?? []).count == 1 })
        #expect(words.allSatisfy { $0.card?.stability == 12.5 }, "Состояние берётся из прямой карточки")
    }

    @Test("Миграция удаляет обратные карточки и оставляет прямые")
    func migrationRemovesRecognitionCards() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let deck = makeDeck(in: context, started: true)
        for word in deck.sortedWords {
            let old = ReCard(direction: .recognition)
            old.word = word
            context.insert(old)
            word.cards = (word.cards ?? []) + [old]
        }
        try context.save()
        #expect(try context.fetchCount(FetchDescriptor<ReCard>()) == 6)

        CardMigration.removeRecognitionCards(in: context)
        CardMigration.removeRecognitionCards(in: context)

        #expect(try context.fetchCount(FetchDescriptor<ReCard>()) == 3)
        #expect(deck.sortedWords.allSatisfy { $0.card?.stability == 12.5 })
    }

    @Test("Демо-колоды из бандла читаются и валидны")
    func demoDecksAreValid() throws {
        for name in ["de_ru_a1", "en_ru_a1"] {
            let payload = try #require(
                DemoDeckLoader.loadPayload(named: name),
                "Демо-колода \(name) должна читаться из бандла"
            )
            #expect(payload.words.count >= 40, "В демо-колоде \(name) слишком мало слов")
            #expect(payload.words.allSatisfy { !$0.word.isEmpty && !$0.translations.isEmpty })
            // Иначе часть слов, например совпадающие формы глагола, потерялась бы при импорте.
            let keys = Set(payload.words.map { WordKey.make(text: $0.word, translations: $0.translations) })
            #expect(keys.count == payload.words.count, "В демо-колоде \(name) есть дубликаты")
        }
    }
}
