import Foundation
import Observation
import TouchGrassCore
import TouchGrassScreenTime

/// The app's single source of truth. Every change goes through the shared `AppStateStore`
/// so the monitor extension's edits are never overwritten, then the shields are re-synced.
@Observable
final class AppModel {
    static let shared = AppModel()

    private(set) var state: AppState
    private(set) var isScreenTimeApproved = ScreenTimeAuthorization.isApproved
    /// Set when a notification from the shield asks to open the camera.
    var isShowingTouchGrass = false
    /// Explains a rule change that didn't apply straight away.
    var ruleChangeNotice: String?

    @ObservationIgnored private let store: AppStateStore
    @ObservationIgnored private let emergencyUnlockSync = EmergencyUnlockSync()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(store: AppStateStore = AppStateStore()) {
        self.store = store
        #if DEBUG
        DemoState.apply(to: store)
        #endif
        self.state = store.load()
    }

    // MARK: Status

    func isLocked(at now: Date = .now) -> Bool { state.isLocked(at: now) }

    /// Settings are frozen while any Lock is active, including during a Break.
    func settingsFrozen(at now: Date = .now) -> Bool { state.hasActiveLocks(at: now) }

    // MARK: Lifecycle

    /// Reloads state written by extensions or other devices and re-applies the shields.
    func refresh() {
        let now = Date()
        isScreenTimeApproved = ScreenTimeAuthorization.isApproved
        let synced = emergencyUnlockSync.load()
        change(at: now) { state in
            state.reconcile(at: now)
            state.emergencyUnlocks = state.emergencyUnlocks.merged(with: synced)
        }
    }

    func requestScreenTime() async {
        try? await ScreenTimeAuthorization.request()
        isScreenTimeApproved = ScreenTimeAuthorization.isApproved
    }

    // MARK: Setup

    func completeSetup(blockList: BlockList, style: Style, bedtime: Schedule?) {
        let now = Date()
        change(at: now) { state in
            state.blockLists = [blockList]
            state.schedules = bedtime.map { [$0] } ?? []
            state.settings = .preset(style)
            state.settings.defaultBlockListID = blockList.id
            state.hasCompletedSetup = true
            state.reconcile(at: now)
        }
    }

    // MARK: Locking

    func lock(blockListID: UUID? = nil, for duration: TimeInterval? = nil) {
        let now = Date()
        change(at: now) { state in
            guard let id = blockListID ?? state.defaultBlockList?.id else { return }
            let endsAt = state.settings.manualLocksCanHaveDuration ? duration.map(now.addingTimeInterval) : nil
            state.startManualLock(blockListID: id, endsAt: endsAt, at: now)
        }
    }

    func recordTouchGrass() {
        let now = Date()
        change(at: now) { $0.touchGrass(at: now) }
    }

    func useEmergencyUnlock() throws(EmergencyUnlockError) {
        let now = Date()
        state = try store.update { state throws(EmergencyUnlockError) in
            state.emergencyUnlocks = state.emergencyUnlocks.merged(with: emergencyUnlockSync.load())
            try state.useEmergencyUnlock(at: now)
        }
        emergencyUnlockSync.save(state.emergencyUnlocks)
        enforce(at: now)
    }

    // MARK: Rules

    /// Changes Block Lists, Schedules or Settings, starting from any changes already waiting.
    /// Loosening waits for the Reset Time in Strict, and nothing changes while Locked.
    func changeRules(_ body: (inout Rules) -> Void) {
        let now = Date()
        var outcome = RuleChangeOutcome.applied
        change(at: now) { state in
            outcome = state.changeRules(at: now, listCovers: { new, old in new.covers(old) }, body)
            state.reconcile(at: now)
        }
        switch outcome {
        case .applied:
            ruleChangeNotice = nil
        case let .waitingUntil(date):
            ruleChangeNotice = "That loosens your rules, so it takes effect at \(date.formatted(date: .omitted, time: .shortened))."
        case .refusedWhileLocked:
            ruleChangeNotice = "Rules are frozen while you're Locked."
        }
    }

    func cancelPendingRules() {
        change { $0.cancelPendingRules() }
    }

    // MARK: Private

    private func change(at now: Date = .now, _ body: (inout AppState) -> Void) {
        state = store.update(body)
        enforce(at: now)
    }

    private func enforce(at now: Date) {
        Enforcement.sync(state, at: now)
        Enforcement.syncActivities(for: state)
        scheduleRefresh(after: now)
    }

    /// Wakes the app when a Break or timed Lock ends while it's open, so the screen stays current.
    private func scheduleRefresh(after now: Date) {
        refreshTask?.cancel()
        guard let next = state.nextEnforcementChange(after: now) else { return }
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(next.timeIntervalSinceNow + 1))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}
