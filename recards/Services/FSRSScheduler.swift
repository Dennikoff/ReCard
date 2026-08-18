import Foundation
import FSRS

/// Единственное место в проекте, где допускается импорт пакета FSRS.
///
/// Пакет экспортирует типы `Card`, `CardState`, `Rating` и `ReviewLog`. Модели приложения
/// названы иначе (`ReCard`, `ReCardState`, `ReRating`, `ReLog`) именно затем,
/// чтобы эти имена не пересекались.
nonisolated struct FSRSScheduler: Scheduler {
    private let engine: FSRS

    /// - Parameter parameters: по умолчанию — канонические веса шестой версии алгоритма
    ///   с отключённым разбросом интервалов. Разброс полезен на больших колодах, но делает
    ///   поведение невоспроизводимым, что мешает тестам.
    init(parameters: FSRSParameters = FSRSParameters(w: FSRSDefaults.defaultWv6, enableFuzz: false)) {
        self.engine = FSRS(parameters: parameters)
    }

    func schedule(state: CardScheduleState, grade: ReRating, now: Date) throws -> ScheduleResult {
        let card = Card(
            due: state.due,
            stability: state.stability,
            difficulty: state.difficulty,
            elapsedDays: state.elapsedDays,
            scheduledDays: state.scheduledDays,
            learningSteps: state.learningSteps,
            reps: state.reps,
            lapses: state.lapses,
            state: state.state.packageValue,
            lastReview: state.lastReview
        )

        let next = try engine.next(card: card, now: now, grade: grade.packageValue).card

        return ScheduleResult(
            due: next.due,
            stability: next.stability,
            difficulty: next.difficulty,
            elapsedDays: next.elapsedDays,
            scheduledDays: next.scheduledDays,
            learningSteps: next.learningSteps,
            reps: next.reps,
            lapses: next.lapses,
            state: ReCardState(package: next.state),
            lastReview: next.lastReview
        )
    }
}

// MARK: - Преобразование типов

private nonisolated extension ReCardState {
    var packageValue: CardState {
        switch self {
        case .new: return .new
        case .learning: return .learning
        case .review: return .review
        case .relearning: return .relearning
        }
    }

    init(package: CardState) {
        switch package {
        case .new: self = .new
        case .learning: self = .learning
        case .review: self = .review
        case .relearning: self = .relearning
        }
    }
}

private nonisolated extension ReRating {
    var packageValue: Rating {
        switch self {
        case .again: return .again
        case .hard: return .hard
        case .good: return .good
        case .easy: return .easy
        }
    }
}
