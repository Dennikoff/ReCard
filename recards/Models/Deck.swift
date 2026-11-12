import Foundation
import SwiftData

/// Колода слов. Языковая пара задаётся при создании и дальше неизменяема.
@Model
final class Deck {
    var id: UUID = UUID()
    var name: String = ""
    var emoji: String = "📘"

    /// BCP-47 язык изучаемого слова, например `de-DE`. Определяет голос синтезатора.
    var sourceLanguage: String = "de-DE"
    /// BCP-47 язык перевода, например `ru-RU`.
    var targetLanguage: String = "ru-RU"

    /// Участвует ли колода в общих сессиях обучения.
    var isActive: Bool = true
    /// Колода пришла из бандла при первом запуске.
    var isBuiltIn: Bool = false
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Word.deck)
    var words: [Word]? = []

    init(
        name: String,
        emoji: String = "📘",
        sourceLanguage: String,
        targetLanguage: String,
        isActive: Bool = true,
        isBuiltIn: Bool = false
    ) {
        self.id = UUID()
        self.name = name
        self.emoji = emoji
        self.sourceLanguage = sourceLanguage
        self.targetLanguage = targetLanguage
        self.isActive = isActive
        self.isBuiltIn = isBuiltIn
        self.createdAt = Date()
        self.words = []
    }
}

extension Deck {
    /// Слова колоды в стабильном порядке добавления.
    var sortedWords: [Word] {
        (words ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// Слова, к изучению которых пользователь ещё не приступал.
    var newWordsCount: Int {
        (words ?? []).count { $0.isNew }
    }

    /// Слова в работе: начатые, но ещё не выученные.
    var learningWordsCount: Int {
        (words ?? []).count { !$0.isNew && !$0.isLearned }
    }

    var learnedWordsCount: Int {
        (words ?? []).count(where: \.isLearned)
    }

    /// Пара языков в человекочитаемом виде, например «немецкий → русский».
    var languagePairDescription: String {
        let source = LanguageCatalog.displayName(for: sourceLanguage)
        let target = LanguageCatalog.displayName(for: targetLanguage)
        return "\(source) → \(target)"
    }

    /// Ключи слов колоды (текст вместе с переводами) — для отсева дубликатов при импорте.
    var existingWordKeys: Set<String> {
        Set((words ?? []).map { WordKey.make(text: $0.text, translations: $0.translations) })
    }

    /// Файловое представление колоды для экспорта и резервной копии.
    var payload: DeckPayload {
        DeckPayload(
            name: name,
            sourceLanguage: sourceLanguage,
            targetLanguage: targetLanguage,
            words: sortedWords.map(\.payload)
        )
    }
}

extension Word {
    var payload: WordPayload {
        WordPayload(
            word: text,
            translations: translations,
            transcription: transcription,
            example: example,
            exampleTranslation: exampleTranslation
        )
    }
}
