import Foundation
import SwiftData

/// Слово колоды.
///
/// Артикль, если он нужен, является частью `text` (`"der Hund"`). Приложение не разбирает
/// артикли отдельно: при проверке ответа сравнивается строка целиком.
@Model
final class Word {
    var id: UUID = UUID()
    var text: String = ""
    /// Допустимые переводы. Засчитывается любой из них.
    var translations: [String] = []
    var transcription: String? = nil
    var example: String? = nil
    var exampleTranslation: String? = nil

    var createdAt: Date = Date()
    /// Момент, когда слово вышло из состояния «новое». Используется для дневного лимита новых слов.
    var startedAt: Date? = nil

    var deck: Deck?

    @Relationship(deleteRule: .cascade, inverse: \ReCard.word)
    var cards: [ReCard]? = []

    init(
        text: String,
        translations: [String],
        transcription: String? = nil,
        example: String? = nil,
        exampleTranslation: String? = nil
    ) {
        self.id = UUID()
        self.text = text
        self.translations = translations
        self.transcription = transcription
        self.example = example
        self.exampleTranslation = exampleTranslation
        self.createdAt = Date()
        self.cards = []
    }
}

extension Word {
    var isNew: Bool { startedAt == nil }

    /// Слово выучено, когда его карточка уехала в архив.
    var isLearned: Bool { card?.isArchived ?? false }

    /// Карточка повторения слова. Она одна на слово: оба упражнения — печать
    /// и выбор перевода — двигают одно состояние планировщика (SPEC 2.3).
    var card: ReCard? {
        (cards ?? []).first { $0.direction == .production }
    }

    /// Создаёт карточку слова, если её ещё нет.
    func ensureCard() {
        guard card == nil else { return }
        let card = ReCard(direction: .production)
        card.word = self
        cards = (cards ?? []) + [card]
    }
}
