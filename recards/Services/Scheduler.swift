import Foundation

/// Пороговые значения, определяющие поведение планировщика в терминах продукта.
nonisolated enum SchedulingRules {
    /// Устойчивость памяти в днях, начиная с которой карточка считается выученной
    /// и уходит в архив.
    static let learnedStabilityThreshold: Double = 60

    /// Ответ быстрее этого времени считается лёгким.
    static let easyResponseThreshold: TimeInterval = 3
}

/// Снимок состояния карточки, не зависящий от SwiftData.
///
/// Существует, чтобы логику планирования можно было тестировать без хранилища.
nonisolated struct CardScheduleState: Equatable, Sendable {
    var due: Date
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var scheduledDays: Double
    var learningSteps: Int
    var reps: Int
    var lapses: Int
    var state: ReCardState
    var lastReview: Date?

    /// Состояние новой, ни разу не показанной карточки.
    static func empty(due: Date = Date()) -> CardScheduleState {
        CardScheduleState(
            due: due,
            stability: 0,
            difficulty: 0,
            elapsedDays: 0,
            scheduledDays: 0,
            learningSteps: 0,
            reps: 0,
            lapses: 0,
            state: .new,
            lastReview: nil
        )
    }
}

/// Результат планирования следующего показа.
nonisolated struct ScheduleResult: Equatable, Sendable {
    var due: Date
    var stability: Double
    var difficulty: Double
    var elapsedDays: Double
    var scheduledDays: Double
    var learningSteps: Int
    var reps: Int
    var lapses: Int
    var state: ReCardState
    var lastReview: Date?

    /// Карточка достигла порога устойчивости и должна уйти в архив.
    var isLearned: Bool { stability >= SchedulingRules.learnedStabilityThreshold }
}

/// Планировщик интервального повторения.
///
/// Единственная реализация — `FSRSScheduler`. Протокол существует, чтобы тесты
/// и вызывающий код не зависели от конкретного пакета.
nonisolated protocol Scheduler {
    func schedule(state: CardScheduleState, grade: ReRating, now: Date) throws -> ScheduleResult
}

nonisolated extension Scheduler {
    /// Переводит результат проверки ответа в оценку для планировщика.
    ///
    /// Планировщик ожидает четыре градации, а ввод текстом даёт бинарный результат,
    /// поэтому недостающие различия берутся из наличия опечатки и скорости ответа.
    static func grade(for verdict: AnswerVerdict, responseTime: TimeInterval) -> ReRating {
        switch verdict {
        case .incorrect:
            return .again
        case .correctWithTypo:
            return .hard
        case .correct:
            return responseTime < SchedulingRules.easyResponseThreshold ? .easy : .good
        }
    }
}
