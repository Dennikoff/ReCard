import Foundation
import SwiftData

/// Состояние одной карточки повторения в резервной копии.
nonisolated struct BackupCard: Codable, Equatable, Sendable {
    var direction: String
    var isArchived: Bool
    var due: Date
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var scheduledDays: Double
    var learningSteps: Int
    var reps: Int
    var lapses: Int
    var state: String
    var lastReview: Date?
}

/// Слово вместе с прогрессом.
nonisolated struct BackupWord: Codable, Equatable, Sendable {
    var word: String
    var translations: [String]
    var transcription: String?
    var example: String?
    var exampleTranslation: String?
    var createdAt: Date
    var startedAt: Date?
    var cards: [BackupCard]
}

nonisolated struct BackupDeck: Codable, Equatable, Sendable {
    var name: String
    var emoji: String
    var sourceLanguage: String
    var targetLanguage: String
    var isActive: Bool
    var createdAt: Date
    var words: [BackupWord]
}

/// Полный снимок данных приложения.
///
/// Поскольку синхронизации в версии 1.0 нет, удаление приложения означает
/// безвозвратную потерю прогресса. Резервная копия — единственная страховка.
nonisolated struct Backup: Codable, Equatable, Sendable {
    /// Версия формата: позволит распознать файл, созданный будущей версией приложения.
    var formatVersion: Int = 1
    var createdAt: Date
    var decks: [BackupDeck]
}

@MainActor
enum BackupService {

    // MARK: - Создание

    static func makeBackup(in context: ModelContext, now: Date = Date()) -> Backup {
        let descriptor = FetchDescriptor<Deck>(sortBy: [SortDescriptor(\.createdAt)])
        let decks = (try? context.fetch(descriptor)) ?? []

        return Backup(
            createdAt: now,
            decks: decks.map { deck in
                BackupDeck(
                    name: deck.name,
                    emoji: deck.emoji,
                    sourceLanguage: deck.sourceLanguage,
                    targetLanguage: deck.targetLanguage,
                    isActive: deck.isActive,
                    createdAt: deck.createdAt,
                    words: deck.sortedWords.map(makeWord)
                )
            }
        )
    }

    private static func makeWord(_ word: Word) -> BackupWord {
        BackupWord(
            word: word.text,
            translations: word.translations,
            transcription: word.transcription,
            example: word.example,
            exampleTranslation: word.exampleTranslation,
            createdAt: word.createdAt,
            startedAt: word.startedAt,
            cards: [word.card].compactMap { $0 }.map { card in
                BackupCard(
                    direction: card.directionRaw,
                    isArchived: card.isArchived,
                    due: card.due,
                    stability: card.stability,
                    difficulty: card.difficulty,
                    elapsedDays: card.elapsedDays,
                    scheduledDays: card.scheduledDays,
                    learningSteps: card.learningSteps,
                    reps: card.reps,
                    lapses: card.lapses,
                    state: card.stateRaw,
                    lastReview: card.lastReview
                )
            }
        )
    }

    static func encode(_ backup: Backup) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(backup)
    }

    static func decode(_ data: Data) throws -> Backup {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(Backup.self, from: data)
    }

    // MARK: - Восстановление

    /// Заменяет все данные содержимым резервной копии.
    ///
    /// Именно замена, а не слияние: слияние двух состояний прогресса дало бы
    /// неочевидный результат, а пользователь ожидает вернуться к снимку.
    static func restore(_ backup: Backup, into context: ModelContext) throws {
        try deleteAll(in: context)

        for backupDeck in backup.decks {
            let deck = Deck(
                name: backupDeck.name,
                emoji: backupDeck.emoji,
                sourceLanguage: backupDeck.sourceLanguage,
                targetLanguage: backupDeck.targetLanguage,
                isActive: backupDeck.isActive
            )
            deck.createdAt = backupDeck.createdAt
            context.insert(deck)

            for backupWord in backupDeck.words {
                let word = Word(
                    text: backupWord.word,
                    translations: backupWord.translations,
                    transcription: backupWord.transcription,
                    example: backupWord.example,
                    exampleTranslation: backupWord.exampleTranslation
                )
                word.createdAt = backupWord.createdAt
                word.startedAt = backupWord.startedAt
                word.deck = deck
                context.insert(word)
                deck.words = (deck.words ?? []) + [word]

                // Копии из версии с двумя карточками на слово: состояние слова —
                // это прямая карточка, обратная отбрасывается (см. `CardMigration`).
                let backupCards = backupWord.cards.filter {
                    CardDirection(rawValue: $0.direction) != .recognition
                }
                for backupCard in backupCards.prefix(1) {
                    let card = ReCard(direction: .production)
                    card.isArchived = backupCard.isArchived
                    card.due = backupCard.due
                    card.stability = backupCard.stability
                    card.difficulty = backupCard.difficulty
                    card.elapsedDays = backupCard.elapsedDays
                    card.scheduledDays = backupCard.scheduledDays
                    card.learningSteps = backupCard.learningSteps
                    card.reps = backupCard.reps
                    card.lapses = backupCard.lapses
                    card.stateRaw = backupCard.state
                    card.lastReview = backupCard.lastReview
                    card.word = word
                    context.insert(card)
                    word.cards = (word.cards ?? []) + [card]
                }

                // Файл мог прийти без карточки.
                word.ensureCard()
            }
        }

        try context.save()
    }

    // MARK: - Очистка

    static func deleteAll(in context: ModelContext) throws {
        try context.delete(model: ReLog.self)
        try context.delete(model: ReCard.self)
        try context.delete(model: Word.self)
        try context.delete(model: Deck.self)
        try context.save()
    }

    /// Сбрасывает прогресс, сохраняя сами слова.
    static func resetAllProgress(in context: ModelContext) throws {
        let descriptor = FetchDescriptor<Word>()
        for word in (try? context.fetch(descriptor)) ?? [] {
            word.startedAt = nil
            word.card?.resetProgress()
        }
        try context.delete(model: ReLog.self)
        try context.save()
    }

    static func fileName(now: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return "recards-backup-\(formatter.string(from: now)).json"
    }
}
