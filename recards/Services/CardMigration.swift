import Foundation
import SwiftData

/// Приведение старых данных к схеме «одна карточка на слово».
///
/// До перехода у каждого слова было две карточки — по одной на направление,
/// с независимыми состояниями. Теперь состояние одно, и им становится прежняя
/// карточка `production`: печать — основное упражнение, её прогресс ближе всего
/// к тому, насколько слово действительно известно. Карточки `recognition` удаляются.
@MainActor
enum CardMigration {

    /// Удаляет лишние карточки. Повторный вызов ничего не делает.
    static func removeRecognitionCards(in context: ModelContext) {
        let recognition = CardDirection.recognition.rawValue
        let descriptor = FetchDescriptor<ReCard>(
            predicate: #Predicate { $0.directionRaw == recognition }
        )
        guard let cards = try? context.fetch(descriptor), !cards.isEmpty else { return }

        for card in cards {
            context.delete(card)
        }
        // У слова, от которого осталась только обратная карточка, появится прямая.
        for word in (try? context.fetch(FetchDescriptor<Word>())) ?? [] {
            word.ensureCard()
        }
        try? context.save()
    }
}
