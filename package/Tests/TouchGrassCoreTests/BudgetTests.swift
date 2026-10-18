import Foundation
import Testing
@testable import TouchGrassCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

private func date(day: Int = 19, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Suite struct BudgetTests {
    let social = BlockList(name: "Social")

    func makeState(_ style: Style = .strict, resetHour: Int = 0) -> (AppState, Budget) {
        let budget = Budget(name: "Social", blockListID: social.id, minutes: 60)
        var state = AppState(hasCompletedSetup: true, blockLists: [social], budgets: [budget], settings: .preset(style))
        state.settings.resetTime = TimeOfDay(hour: resetHour)
        return (state, budget)
    }

    @Test func usedUpBudgetLocksUntilTheResetTime() {
        var (state, budget) = makeState(resetHour: 4)
        state.startBudgetLock(id: budget.id, at: date(20), calendar: calendar)

        #expect(state.isLocked(at: date(23)))
        #expect(state.locks.first?.endsAt == date(day: 20, 4))
        #expect(state.reason(for: state.locks[0]) == "your Social Budget running out")

        state.reconcile(at: date(day: 20, 4), calendar: calendar)
        #expect(!state.isLocked(at: date(day: 20, 4)))
        #expect(state.locks.isEmpty)
    }

    @Test func budgetDayRunsBetweenResetTimes() {
        let (state, _) = makeState(resetHour: 4)
        #expect(state.budgetDay(containing: date(2), calendar: calendar) == DateInterval(start: date(day: 18, 4), end: date(4)))
        #expect(state.budgetDay(containing: date(4), calendar: calendar) == DateInterval(start: date(4), end: date(day: 20, 4)))
    }

    @Test func strictTouchGrassGivesABreakFromABudget() {
        var (state, budget) = makeState(.strict)
        state.startBudgetLock(id: budget.id, at: date(20), calendar: calendar)
        state.touchGrass(at: date(21))
        #expect(!state.isLocked(at: date(21, 10)))
        #expect(state.isLocked(at: date(21, 15)))
    }

    @Test func flexibleTouchGrassEndsTheBudgetForTheDay() {
        var (state, budget) = makeState(.flexible)
        state.startBudgetLock(id: budget.id, at: date(20), calendar: calendar)
        state.touchGrass(at: date(21))
        // A repeated threshold callback the same day doesn't re-lock.
        state.startBudgetLock(id: budget.id, at: date(22), calendar: calendar)
        #expect(!state.isLocked(at: date(22)))
    }

    @Test func disabledBudgetDoesNotLock() {
        var (state, budget) = makeState()
        state.budgets[0].isEnabled = false
        state.startBudgetLock(id: budget.id, at: date(20), calendar: calendar)
        #expect(!state.isLocked(at: date(20)))
    }

    @Test func raisingABudgetIsLooseningButLoweringIsNot() {
        var (state, _) = makeState(.strict)
        let covers: (BlockList, BlockList) -> Bool = { _, _ in true }
        #expect(state.changeRules(at: date(12), calendar: calendar, listCovers: covers) { $0.budgets[0].minutes = 30 } == .applied)
        #expect(state.changeRules(at: date(12), calendar: calendar, listCovers: covers) { $0.budgets[0].minutes = 90 } == .waitingUntil(date(day: 20, 0)))
    }

    @Test func movingTheResetTimeIsLoosening() {
        var (state, _) = makeState(.strict)
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: { _, _ in true }) {
            $0.settings.resetTime = TimeOfDay(hour: 4)
        }
        #expect(outcome == .waitingUntil(date(day: 20, 0)))
    }
}
