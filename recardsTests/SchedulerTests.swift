import Testing
import Foundation
@testable import recards

@Suite("Перевод результата проверки в оценку")
struct GradeMappingTests {

    @Test("Неверный ответ даёт again")
    func incorrectMapsToAgain() {
        #expect(FSRSScheduler.grade(for: .incorrect, responseTime: 1) == .again)
        #expect(FSRSScheduler.grade(for: .incorrect, responseTime: 30) == .again)
    }

    @Test("Опечатка даёт hard независимо от скорости")
    func typoMapsToHard() {
        #expect(FSRSScheduler.grade(for: .correctWithTypo, responseTime: 0.5) == .hard)
        #expect(FSRSScheduler.grade(for: .correctWithTypo, responseTime: 20) == .hard)
    }

    @Test("Быстрый верный ответ даёт easy, обычный — good")
    func correctDependsOnSpeed() {
        #expect(FSRSScheduler.grade(for: .correct, responseTime: 1.0) == .easy)
        #expect(FSRSScheduler.grade(for: .correct, responseTime: 2.99) == .easy)
        #expect(FSRSScheduler.grade(for: .correct, responseTime: 3.0) == .good)
        #expect(FSRSScheduler.grade(for: .correct, responseTime: 10) == .good)
    }
}

@Suite("Планировщик FSRS")
struct FSRSSchedulerTests {

    private let scheduler = FSRSScheduler()
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    @Test("Новая карточка после верного ответа получает будущий срок")
    func newCardIsScheduledForward() throws {
        let result = try scheduler.schedule(state: .empty(due: now), grade: .good, now: now)

        #expect(result.due > now)
        #expect(result.reps == 1)
        #expect(result.lapses == 0)
        #expect(result.state != .new)
        #expect(result.lastReview == now)
    }

    @Test("Оценка easy назначает срок не раньше, чем good")
    func easyIsNotShorterThanGood() throws {
        let good = try scheduler.schedule(state: .empty(due: now), grade: .good, now: now)
        let easy = try scheduler.schedule(state: .empty(due: now), grade: .easy, now: now)

        #expect(easy.due >= good.due)
        #expect(easy.stability >= good.stability)
    }

    @Test("Оценка again не увеличивает устойчивость больше, чем good")
    func againIsWeakerThanGood() throws {
        let again = try scheduler.schedule(state: .empty(due: now), grade: .again, now: now)
        let good = try scheduler.schedule(state: .empty(due: now), grade: .good, now: now)

        #expect(again.stability <= good.stability)
        #expect(again.due <= good.due)
    }

    @Test("Забытая после успешного повторения карточка увеличивает счётчик провалов")
    func lapseIsCountedOnForgottenReview() throws {
        var state = CardScheduleState.empty(due: now)
        var moment = now

        // Доводим карточку до состояния review чередой верных ответов.
        for _ in 0..<6 {
            let result = try scheduler.schedule(state: state, grade: .good, now: moment)
            state = Self.applying(result, to: state)
            moment = result.due
            if state.state == .review { break }
        }

        try #require(state.state == .review, "Карточка должна дойти до состояния review")
        let lapsesBefore = state.lapses

        let forgotten = try scheduler.schedule(state: state, grade: .again, now: moment)
        #expect(forgotten.lapses == lapsesBefore + 1)
        #expect(forgotten.state == .relearning)
    }

    @Test("Устойчивость растёт при последовательных верных ответах")
    func stabilityGrowsOverTime() throws {
        var state = CardScheduleState.empty(due: now)
        var moment = now
        var previousStability = 0.0

        for _ in 0..<5 {
            let result = try scheduler.schedule(state: state, grade: .good, now: moment)
            #expect(result.stability >= previousStability)
            previousStability = result.stability
            state = Self.applying(result, to: state)
            moment = result.due
        }

        #expect(previousStability > 0)
    }

    @Test("Карточка признаётся выученной при достижении порога устойчивости")
    func learnedThresholdMatchesRules() {
        let below = ScheduleResult(
            due: now, stability: SchedulingRules.learnedStabilityThreshold - 0.1,
            difficulty: 5, elapsedDays: 0, scheduledDays: 0, learningSteps: 0,
            reps: 1, lapses: 0, state: .review, lastReview: now
        )
        let atThreshold = ScheduleResult(
            due: now, stability: SchedulingRules.learnedStabilityThreshold,
            difficulty: 5, elapsedDays: 0, scheduledDays: 0, learningSteps: 0,
            reps: 1, lapses: 0, state: .review, lastReview: now
        )

        #expect(below.isLearned == false)
        #expect(atThreshold.isLearned)
    }

    /// Переносит результат планирования обратно в состояние карточки.
    private static func applying(
        _ result: ScheduleResult,
        to state: CardScheduleState
    ) -> CardScheduleState {
        var state = state
        state.due = result.due
        state.stability = result.stability
        state.difficulty = result.difficulty
        state.elapsedDays = result.elapsedDays
        state.scheduledDays = result.scheduledDays
        state.learningSteps = result.learningSteps
        state.reps = result.reps
        state.lapses = result.lapses
        state.state = result.state
        state.lastReview = result.lastReview
        return state
    }
}
