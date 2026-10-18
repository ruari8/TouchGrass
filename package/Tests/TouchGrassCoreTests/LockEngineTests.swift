import Foundation
import Testing
@testable import TouchGrassCore

private let start = Date(timeIntervalSince1970: 1_800_000_000)
private func minutes(_ n: Double) -> Date { start.addingTimeInterval(n * 60) }

private func makeState(_ style: Style = .strict) -> (AppState, social: UUID, everything: UUID) {
    let social = BlockList(name: "Social")
    let everything = BlockList(name: "Everything")
    var state = AppState(hasCompletedSetup: true, blockLists: [social, everything], settings: .preset(style))
    state.settings.defaultBlockListID = social.id
    return (state, social.id, everything.id)
}

@Suite struct ManualLockTests {
    @Test func manualLockBlocksUntilTouchGrass() {
        var (state, social, _) = makeState()
        state.startManualLock(blockListID: social, at: start)

        #expect(state.isLocked(at: minutes(600)))
        #expect(state.enforcedBlockListIDs(at: minutes(1)) == [social])

        state.touchGrass(at: minutes(601))
        #expect(!state.isLocked(at: minutes(601)))
        #expect(state.locks.isEmpty)
        #expect(state.grassCount == 1)
    }

    @Test func lockingTheSameListTwiceKeepsOneLock() {
        var (state, social, _) = makeState()
        state.startManualLock(blockListID: social, at: start)
        state.startManualLock(blockListID: social, at: minutes(5))
        #expect(state.locks.count == 1)
    }

    @Test func unknownBlockListIsIgnored() {
        var (state, _, _) = makeState()
        #expect(state.startManualLock(blockListID: UUID(), at: start) == nil)
        #expect(!state.isLocked(at: start))
    }

    @Test func manualLockWithDurationEndsOnItsOwn() {
        var (state, social, _) = makeState(.flexible)
        state.startManualLock(blockListID: social, endsAt: minutes(60), at: start)
        #expect(state.isLocked(at: minutes(59)))
        #expect(!state.isLocked(at: minutes(60)))
        state.pruneEndedLocks(at: minutes(60))
        #expect(state.locks.isEmpty)
    }
}

@Suite struct TouchGrassTests {
    /// The worked example from the design: a Social Budget runs out at 8pm, a 10pm–7am Schedule
    /// locks Everything, and the user touches grass once at 10:30pm.
    @Test func strictTouchGrassGivesOneBreakForEveryLock() {
        var (state, social, everything) = makeState(.strict)
        let budget = LockSource.budget(UUID())
        let schedule = LockSource.schedule(UUID())
        state.startAutomaticLock(source: budget, blockListID: social, endsAt: minutes(240), at: start)
        state.startAutomaticLock(source: schedule, blockListID: everything, endsAt: minutes(660), at: minutes(120))

        state.touchGrass(at: minutes(150))

        #expect(!state.isLocked(at: minutes(150)))
        #expect(state.breakEnds(at: minutes(150)) == minutes(165))
        #expect(state.hasActiveLocks(at: minutes(150)))
        #expect(state.enforcedBlockListIDs(at: minutes(165)) == [social, everything])
        #expect(state.grassCount == 1)
    }

    @Test func flexibleTouchGrassDismissesAutomaticLocks() {
        var (state, social, _) = makeState(.flexible)
        let budget = LockSource.budget(UUID())
        state.startAutomaticLock(source: budget, blockListID: social, endsAt: minutes(240), at: start)

        state.touchGrass(at: minutes(10))

        #expect(!state.isLocked(at: minutes(10)))
        #expect(!state.isLocked(at: minutes(239)))
        #expect(!state.hasActiveLocks(at: minutes(10)))
        // The trigger firing again in the same run doesn't bring the Lock back.
        state.startAutomaticLock(source: budget, blockListID: social, endsAt: minutes(240), at: minutes(20))
        #expect(!state.isLocked(at: minutes(20)))
    }

    @Test func lockThatStartsDuringABreakLocksImmediately() {
        var (state, social, everything) = makeState(.strict)
        state.startAutomaticLock(source: .budget(UUID()), blockListID: social, endsAt: minutes(240), at: start)
        state.touchGrass(at: minutes(100))
        state.startAutomaticLock(source: .schedule(UUID()), blockListID: everything, endsAt: minutes(600), at: minutes(105))

        #expect(state.enforcedBlockListIDs(at: minutes(105)) == [everything])
        #expect(state.enforcedBlockListIDs(at: minutes(115)) == [social, everything])
    }

    @Test func breakNeverOutlastsTheLock() {
        var (state, social, _) = makeState(.strict)
        state.startAutomaticLock(source: .schedule(UUID()), blockListID: social, endsAt: minutes(10), at: start)
        state.touchGrass(at: minutes(5))
        #expect(state.locks.first?.pausedUntil == minutes(10))
    }

    @Test func touchGrassOnABreakDoesNotUndismissALock() {
        var (state, social, _) = makeState(.flexible)
        state.startAutomaticLock(source: .budget(UUID()), blockListID: social, endsAt: minutes(240), at: start)
        state.touchGrass(at: minutes(10))
        state.settings.apply(.strict)
        state.touchGrass(at: minutes(20))
        #expect(!state.isLocked(at: minutes(60)))
    }
}

@Suite struct EmergencyUnlockTests {
    @Test func startsWithThreeAndEachComesBackAfterThirtyDays() throws {
        var ledger = EmergencyUnlockLedger()
        #expect(ledger.available(at: start) == 3)

        try ledger.use(at: start)
        try ledger.use(at: minutes(1))
        try ledger.use(at: minutes(2))
        #expect(ledger.available(at: minutes(3)) == 0)
        #expect(throws: EmergencyUnlockError.noneLeft) { try ledger.use(at: minutes(3)) }

        let thirtyDays = EmergencyUnlockLedger.refillInterval / 60
        #expect(ledger.nextRefill(at: minutes(3)) == minutes(thirtyDays))
        #expect(ledger.available(at: minutes(thirtyDays)) == 1)
        #expect(ledger.available(at: minutes(thirtyDays + 2)) == 3)
    }

    @Test func mergedUsesNeverGoBelowZero() throws {
        var a = EmergencyUnlockLedger()
        var b = EmergencyUnlockLedger()
        for minute in 0..<3 {
            try a.use(at: minutes(Double(minute)))
            try b.use(at: minutes(Double(minute) + 0.5))
        }
        #expect(a.merged(with: b).available(at: minutes(5)) == 0)
    }

    @Test func mergingKeepsUsesFromBothSources() throws {
        var a = EmergencyUnlockLedger()
        var b = EmergencyUnlockLedger()
        try a.use(at: start)
        try b.use(at: minutes(1))
        #expect(a.merged(with: b).available(at: minutes(2)) == 1)
        #expect(a.merged(with: a).available(at: minutes(2)) == 2)
    }

    @Test func emergencyUnlockEndsEverythingEvenInStrict() throws {
        var (state, social, everything) = makeState(.strict)
        state.startManualLock(blockListID: social, at: start)
        state.startAutomaticLock(source: .schedule(UUID()), blockListID: everything, endsAt: minutes(600), at: start)

        try state.useEmergencyUnlock(at: minutes(10))

        #expect(!state.isLocked(at: minutes(10)))
        #expect(!state.isLocked(at: minutes(500)))
        #expect(state.emergencyUnlocks.available(at: minutes(10)) == 2)
        #expect(state.grassCount == 0)
    }
}

@Suite struct SettingsTests {
    @Test func presetsReportTheirStyle() {
        #expect(Settings.preset(.strict).style == .strict)
        #expect(Settings.preset(.flexible).style == .flexible)
        var custom = Settings.preset(.strict)
        custom.touchGrassGivesBreak = false
        #expect(custom.style == nil)
    }
}

@Suite struct AppStateStoreTests {
    @Test func updatePersistsAndFailedUpdateSavesNothing() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        let store = AppStateStore(fileURL: url)
        try store.update { $0.grassCount = 4 }
        #expect(try store.load().grassCount == 4)

        struct Failure: Error {}
        var ranWhileLocked = false
        #expect(throws: Failure.self) {
            try store.update({ state in
                state.grassCount = 99
                throw Failure()
            }, whileLocked: { _ in ranWhileLocked = true })
        }
        #expect(try store.load().grassCount == 4)
        #expect(!ranWhileLocked)
    }

    @Test func corruptFileIsAnErrorNotAFreshState() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID()).json")
        try Data("not json".utf8).write(to: url)
        let store = AppStateStore(fileURL: url)
        #expect(throws: AppStateStore.StoreError.self) { try store.load() }
        #expect(throws: AppStateStore.StoreError.self) { try store.update { $0.grassCount = 1 } }
        #expect(try Data(contentsOf: url) == Data("not json".utf8))
    }

    @Test func missingFieldsDecodeToDefaults() throws {
        let state = try JSONDecoder().decode(AppState.self, from: Data(#"{"grassCount": 2}"#.utf8))
        #expect(state.grassCount == 2)
        #expect(state.settings == .preset(.strict))
    }
}
