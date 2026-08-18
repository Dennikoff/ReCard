import Foundation
import SwiftData

/// Запись об одном ответе пользователя.
///
/// В версии 1.0 нигде не читается. Существует потому, что данные, которые не собраны сейчас,
/// невозможно собрать задним числом: на них будут строиться статистика и подстройка
/// параметров планировщика.
///
/// Связи с `ReCard` намеренно нет — только идентификатор, чтобы логи переживали
/// удаление карточки.
@Model
final class ReLog {
    var id: UUID = UUID()
    var cardID: UUID = UUID()
    var wordID: UUID = UUID()

    var gradeRaw: Int = ReRating.good.rawValue
    /// Состояние карточки до применения оценки.
    var stateRaw: String = ReCardState.new.rawValue
    var directionRaw: String = CardDirection.production.rawValue

    var reviewedAt: Date = Date()
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var responseTimeMS: Int = 0

    init(
        cardID: UUID,
        wordID: UUID,
        grade: ReRating,
        state: ReCardState,
        direction: CardDirection,
        reviewedAt: Date = Date(),
        elapsedDays: Double = 0,
        scheduledDays: Double = 0,
        responseTimeMS: Int = 0
    ) {
        self.id = UUID()
        self.cardID = cardID
        self.wordID = wordID
        self.gradeRaw = grade.rawValue
        self.stateRaw = state.rawValue
        self.directionRaw = direction.rawValue
        self.reviewedAt = reviewedAt
        self.elapsedDays = elapsedDays
        self.scheduledDays = scheduledDays
        self.responseTimeMS = responseTimeMS
    }
}

extension ReLog {
    var grade: ReRating { ReRating(rawValue: gradeRaw) ?? .good }
    var state: ReCardState { ReCardState(rawValue: stateRaw) ?? .new }
    var direction: CardDirection { CardDirection(rawValue: directionRaw) ?? .production }
}
