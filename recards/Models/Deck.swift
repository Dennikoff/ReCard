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
}
