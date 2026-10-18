import Foundation
import Testing
@testable import TouchGrassCore

private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
}()

/// 2026-10-19 is a Monday (weekday 2).
private func date(day: Int = 19, _ hour: Int, _ minute: Int = 0) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
}

@Suite struct ScheduleWindowTests {
    let list = UUID()

    @Test func overnightWindowSpansMidnight() {
        let bedtime = Schedule(name: "Bedtime", blockListID: list, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        #expect(bedtime.window(containing: date(21, 59), calendar: calendar) == nil)
        #expect(bedtime.window(containing: date(23), calendar: calendar) == DateInterval(start: date(22), end: date(day: 20, 7)))
        #expect(bedtime.window(containing: date(day: 20, 6, 59), calendar: calendar)?.end == date(day: 20, 7))
        #expect(bedtime.window(containing: date(day: 20, 7), calendar: calendar) == nil)
    }

    @Test func weekdaysApplyToTheDayAWindowStarts() {
        // Weekdays only: Monday to Friday.
        let work = Schedule(name: "Work", blockListID: list, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 2), weekdays: [2, 3, 4, 5, 6])
        #expect(work.window(containing: date(23), calendar: calendar) != nil)
        // Sunday night's window doesn't exist, but Monday's 1am is still inside Sunday's slot, so it's off.
        #expect(work.window(containing: date(1), calendar: calendar) == nil)
        // Saturday 1am belongs to Friday night's window.
        #expect(work.window(containing: date(day: 24, 1), calendar: calendar) != nil)
    }

    @Test func nextStartSkipsDaysOff() {
        let weekend = Schedule(name: "Weekend", blockListID: list, start: TimeOfDay(hour: 9), end: TimeOfDay(hour: 17), weekdays: [1, 7])
        #expect(weekend.nextStart(after: date(12), calendar: calendar) == date(day: 24, 9))
    }

    @Test func windowEndsAtTheClockTimeAcrossAClockChange() {
        var london = Calendar(identifier: .gregorian)
        london.timeZone = TimeZone(identifier: "Europe/London")!
        let bedtime = Schedule(name: "Bedtime", blockListID: list, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        // Clocks go back at 2am on Sunday 25 October 2026.
        let saturdayNight = london.date(from: DateComponents(year: 2026, month: 10, day: 24, hour: 23))!
        let window = bedtime.window(containing: saturdayNight, calendar: london)
        #expect(window?.end == london.date(from: DateComponents(year: 2026, month: 10, day: 25, hour: 7)))
    }

    @Test func coversAccountsForTheDayAfterMidnight() {
        // Monday 23:00 to Tuesday 01:00 doesn't cover Monday 00:00 to 01:00.
        let late = Schedule(name: "Late", blockListID: list, start: TimeOfDay(hour: 23), end: TimeOfDay(hour: 1), weekdays: [2])
        let early = Schedule(name: "Early", blockListID: list, start: TimeOfDay(hour: 0), end: TimeOfDay(hour: 1), weekdays: [2])
        #expect(!late.covers(early))
        let tuesdayEarly = Schedule(name: "Early", blockListID: list, start: TimeOfDay(hour: 0), end: TimeOfDay(hour: 1), weekdays: [3])
        #expect(late.covers(tuesdayEarly))
    }

    @Test func coversComparesWindowsAndDays() {
        let night = Schedule(name: "Night", blockListID: list, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        var shorter = night
        shorter.start = TimeOfDay(hour: 23)
        #expect(night.covers(shorter))
        #expect(!shorter.covers(night))

        var fewerDays = night
        fewerDays.weekdays = [2]
        #expect(!fewerDays.covers(night))

        var off = night
        off.isEnabled = false
        #expect(!off.covers(night))
        #expect(night.covers(off))
    }
}

@Suite struct ScheduleLockTests {
    @Test func reconcileStartsAndEndsScheduleLocks() {
        let everything = BlockList(name: "Everything")
        let bedtime = Schedule(name: "Bedtime", blockListID: everything.id, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        var state = AppState(hasCompletedSetup: true, blockLists: [everything], schedules: [bedtime])

        state.reconcile(at: date(21), calendar: calendar)
        #expect(!state.isLocked(at: date(21)))

        state.reconcile(at: date(22), calendar: calendar)
        #expect(state.isLocked(at: date(22)))
        #expect(state.reason(for: state.locks[0]) == "your Bedtime Schedule")

        state.reconcile(at: date(23), calendar: calendar)
        #expect(state.locks.count == 1)

        state.reconcile(at: date(day: 20, 7), calendar: calendar)
        #expect(state.locks.isEmpty)
    }

    @Test func flexibleTouchGrassEndsTonightButNotTomorrow() {
        let everything = BlockList(name: "Everything")
        let bedtime = Schedule(name: "Bedtime", blockListID: everything.id, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        var state = AppState(hasCompletedSetup: true, blockLists: [everything], schedules: [bedtime], settings: .preset(.flexible))

        state.reconcile(at: date(22), calendar: calendar)
        state.touchGrass(at: date(22, 30))
        state.reconcile(at: date(23), calendar: calendar)
        #expect(!state.isLocked(at: date(23)))

        state.reconcile(at: date(day: 20, 22), calendar: calendar)
        #expect(state.isLocked(at: date(day: 20, 22)))
    }
}

@Suite struct RuleChangeTests {
    let social = BlockList(name: "Social")
    let alwaysCovers: (BlockList, BlockList) -> Bool = { _, _ in true }

    func makeState(_ style: Style) -> AppState {
        AppState(
            hasCompletedSetup: true,
            blockLists: [social],
            schedules: [Schedule(name: "Bedtime", blockListID: social.id, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))],
            settings: .preset(style)
        )
    }

    @Test func strictTighteningAppliesAtOnce() {
        var state = makeState(.strict)
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { rules in
            rules.schedules[0].start = TimeOfDay(hour: 21)
        }
        #expect(outcome == .applied)
        #expect(state.schedules[0].start == TimeOfDay(hour: 21))
    }

    @Test func strictLooseningWaitsForTheResetTime() {
        var state = makeState(.strict)
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { rules in
            rules.schedules.removeAll()
        }
        #expect(outcome == .waitingUntil(date(day: 20, 0)))
        #expect(state.schedules.count == 1)
        #expect(state.upcomingRules.schedules.isEmpty)
        #expect(state.nextEnforcementChange(after: date(12)) == date(day: 20, 0))

        state.reconcile(at: date(day: 20, 0), calendar: calendar)
        #expect(state.schedules.isEmpty)
        #expect(state.pendingRules == nil)
    }

    @Test func removingAppsFromAListIsLoosening() {
        var state = makeState(.strict)
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: { _, _ in false }) { rules in
            rules.blockLists[0].itemCount = 1
        }
        #expect(outcome == .waitingUntil(date(day: 20, 0)))
    }

    @Test func switchingToFlexibleIsLoosening() {
        var state = makeState(.strict)
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { $0.settings.apply(.flexible) }
        #expect(outcome == .waitingUntil(date(day: 20, 0)))
        #expect(state.settings.style == .strict)
    }

    @Test func flexibleLooseningAppliesAtOnce() {
        var state = makeState(.flexible)
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { $0.schedules.removeAll() }
        #expect(outcome == .applied)
        #expect(state.schedules.isEmpty)
    }

    @Test func rulesAreFrozenWhileLocked() {
        var state = makeState(.flexible)
        state.startManualLock(blockListID: social.id, at: date(12))
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { $0.schedules.removeAll() }
        #expect(outcome == .refusedWhileLocked)
        #expect(state.schedules.count == 1)
    }

    @Test func pendingLooseningWaitsForActiveLocksToEnd() {
        var state = makeState(.strict)
        // At 9pm, delete the 10pm–7am Schedule. It waits for midnight, when Bedtime is running.
        state.changeRules(at: date(21), calendar: calendar, listCovers: alwaysCovers) { $0.schedules.removeAll() }
        state.reconcile(at: date(22), calendar: calendar)
        state.reconcile(at: date(day: 20, 0), calendar: calendar)
        #expect(state.isLocked(at: date(day: 20, 0)))
        #expect(state.schedules.count == 1)

        state.reconcile(at: date(day: 20, 7), calendar: calendar)
        #expect(state.schedules.isEmpty)
        #expect(!state.isLocked(at: date(day: 20, 7)))
    }

    @Test func tighteningAppliesAtOnceEvenWithLooseningWaiting() {
        var state = makeState(.strict)
        state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { $0.settings.breakMinutes = 60 }
        let extra = Schedule(name: "Lunch", blockListID: social.id, start: TimeOfDay(hour: 12), end: TimeOfDay(hour: 13))
        let outcome = state.changeRules(at: date(12, 5), calendar: calendar, listCovers: alwaysCovers) { $0.schedules.append(extra) }
        #expect(outcome == .applied)
        #expect(state.schedules.count == 2)
        #expect(state.settings.breakMinutes == 15)
        #expect(state.upcomingRules.settings.breakMinutes == 60)
        #expect(state.upcomingRules.schedules.count == 2)
    }

    @Test func switchingTheDefaultToASmallerListIsLoosening() {
        var state = makeState(.strict)
        let small = BlockList(name: "Small")
        state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { $0.blockLists.append(small) }
        let outcome = state.changeRules(at: date(12), calendar: calendar, listCovers: { new, old in new.id == old.id }) {
            $0.settings.defaultBlockListID = small.id
        }
        #expect(outcome == .waitingUntil(date(day: 20, 0)))
    }

    @Test func cancellingWaitingChangesIsFrozenWhileLocked() {
        var state = makeState(.strict)
        state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { $0.schedules.removeAll() }
        state.startManualLock(blockListID: social.id, at: date(13))
        #expect(state.cancelPendingRules(at: date(13)) == .refusedWhileLocked)
        #expect(state.pendingRules != nil)
    }

    @Test func deletingABlockListRemovesItsSchedules() {
        var state = makeState(.flexible)
        let other = BlockList(name: "Other")
        state.changeRules(at: date(12), calendar: calendar, listCovers: alwaysCovers) { rules in
            rules.blockLists = [other]
        }
        #expect(state.schedules.isEmpty)
    }
}

@Suite struct EarlyWakeTests {
    @Test func scheduleLockStartsWhenIOSCallsSlightlyEarly() {
        let list = BlockList(name: "Everything")
        let bedtime = Schedule(name: "Bedtime", blockListID: list.id, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
        var state = AppState(hasCompletedSetup: true, blockLists: [list], schedules: [bedtime])
        state.startScheduleLock(id: bedtime.id, at: date(21, 59).addingTimeInterval(30), calendar: calendar)
        #expect(state.locks.first?.endsAt == date(day: 20, 7))
    }
}
