import Foundation
import SwiftData

/// Карточка одного направления с собственным состоянием интервального повторения.
///
/// Названа `ReCard`, а не `Card`, потому что имя `Card` занято пакетом FSRS.
@Model
final class ReCard {
    var id: UUID = UUID()

    /// Сырое значение `CardDirection`. SwiftData не хранит перечисления напрямую.
    var directionRaw: String = CardDirection.production.rawValue
    /// Карточка выучена и выведена из ротации.
    var isArchived: Bool = false

    // Состояние планировщика
    var due: Date = Date()
    var stability: Double = 0
    var difficulty: Double = 0
    var elapsedDays: Double = 0
    var scheduledDays: Double = 0
    var learningSteps: Int = 0
    var reps: Int = 0
    var lapses: Int = 0
    var stateRaw: String = ReCardState.new.rawValue
    var lastReview: Date? = nil

    var word: Word?

    init(direction: CardDirection, due: Date = AppClock.now) {
        self.id = UUID()
        self.directionRaw = direction.rawValue
        self.due = due
    }
}

extension ReCard {
    var direction: CardDirection {
        get { CardDirection(rawValue: directionRaw) ?? .production }
        set { directionRaw = newValue.rawValue }
    }

    var state: ReCardState {
        get { ReCardState(rawValue: stateRaw) ?? .new }
        set { stateRaw = newValue.rawValue }
    }

    /// Снимок состояния для передачи в планировщик, не завязанный на SwiftData.
    var scheduleState: CardScheduleState {
        CardScheduleState(
            due: due,
            stability: stability,
            difficulty: difficulty,
            elapsedDays: elapsedDays,
            scheduledDays: scheduledDays,
            learningSteps: learningSteps,
            reps: reps,
            lapses: lapses,
            state: state,
            lastReview: lastReview
        )
    }

    /// Записывает результат планирования и архивирует карточку, если она достигла порога.
    func apply(_ result: ScheduleResult) {
        due = result.due
        stability = result.stability
        difficulty = result.difficulty
        elapsedDays = result.elapsedDays
        scheduledDays = result.scheduledDays
        learningSteps = result.learningSteps
        reps = result.reps
        lapses = result.lapses
        state = result.state
        lastReview = result.lastReview

        if result.stability >= SchedulingRules.learnedStabilityThreshold {
            isArchived = true
        }
    }

    /// Возвращает карточку в ротацию, сбрасывая состояние в начальное.
    func resetProgress(now: Date = AppClock.now) {
        isArchived = false
        due = now
        stability = 0
        difficulty = 0
        elapsedDays = 0
        scheduledDays = 0
        learningSteps = 0
        reps = 0
        lapses = 0
        state = .new
        lastReview = nil
    }
}
