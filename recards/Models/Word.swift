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

    /// Слово выучено, когда все его карточки уехали в архив.
    var isLearned: Bool {
        let cards = cards ?? []
        return !cards.isEmpty && cards.allSatisfy(\.isArchived)
    }

    func card(for direction: CardDirection) -> ReCard? {
        (cards ?? []).first { $0.direction == direction }
    }

    /// Создаёт недостающие карточки обоих направлений.
    func ensureCards() {
        for direction in CardDirection.allCases where card(for: direction) == nil {
            let card = ReCard(direction: direction)
            card.word = self
            cards = (cards ?? []) + [card]
        }
    }
}
