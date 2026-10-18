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
    /// Explains a change that didn't apply straight away, or couldn't be saved.
    var notice: String?

    @ObservationIgnored private let store: AppStateStore
    @ObservationIgnored private let emergencyUnlockSync = EmergencyUnlockSync()
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(store: AppStateStore = AppStateStore()) {
        self.store = store
        #if DEBUG
        DemoState.apply(to: store)
        #endif
        do {
            self.state = try store.load()
        } catch {
            self.state = AppState()
            self.notice = "Touch Grass couldn't read its saved settings. Restart the app; if it keeps happening, reinstall it."
        }
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
        if LockActions.takeTouchGrassRequest(), state.hasCompletedSetup {
            isShowingTouchGrass = true
        }
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

    func completeSetup(blockList: BlockList, style: Style, bedtime: Schedule?, budget: Budget?) {
        let now = Date()
        change(at: now) { state in
            state.blockLists = [blockList]
            state.schedules = bedtime.map { [$0] } ?? []
            state.budgets = budget.map { [$0] } ?? []
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
        change(at: now) { state in
            state.touchGrass(at: now)
            // Waiting rule changes that fell due during the Lock can apply now.
            state.reconcile(at: now)
        }
    }

    /// Only records the use in iCloud once it's saved locally, so a failed save doesn't spend one.
    func useEmergencyUnlock() {
        let now = Date()
        let synced = emergencyUnlockSync.load()
        let saved = change(at: now) { state in
            state.emergencyUnlocks = state.emergencyUnlocks.merged(with: synced)
            try state.useEmergencyUnlock(at: now)
            state.reconcile(at: now)
        }
        if saved {
            emergencyUnlockSync.save(state.emergencyUnlocks, at: now)
        }
    }

    // MARK: Rules

    /// Changes Block Lists, Schedules or Settings, starting from any changes already waiting.
    /// Loosening waits for the Reset Time in Strict, and nothing changes while Locked.
    func changeRules(_ body: (inout Rules) -> Void) {
        let now = Date()
        var outcome = RuleChangeOutcome.applied
        let saved = change(at: now) { state in
            outcome = state.changeRules(at: now, listCovers: { new, old in new.covers(old) }, body)
            state.reconcile(at: now)
        }
        if saved { show(outcome) }
    }

    func cancelPendingRules() {
        let now = Date()
        var outcome = RuleChangeOutcome.applied
        if change(at: now, { outcome = $0.cancelPendingRules(at: now) }) {
            show(outcome)
        }
    }

    // MARK: Private

    private func show(_ outcome: RuleChangeOutcome) {
        switch outcome {
        case .applied:
            break
        case let .waitingUntil(date):
            notice = "That loosens your rules, so it takes effect at \(date.formatted(date: .omitted, time: .shortened))."
        case .refusedWhileLocked:
            notice = "Rules are frozen while you're Locked."
        }
    }

    /// Saves a change and applies its shields while still holding the state file, so the monitor
    /// extension can't interleave a change and overwrite these shields with stale ones.
    /// Returns false, and shows why, if nothing was saved.
    @discardableResult
    private func change(at now: Date = .now, _ body: (inout AppState) throws -> Void) -> Bool {
        do {
            state = try store.update(body) { Enforcement.applyShields(for: $0, at: now) }
            Enforcement.scheduleBackgroundWork(for: state, at: now)
            scheduleRefresh(after: now)
            return true
        } catch EmergencyUnlockError.noneLeft {
            notice = "You have no Emergency Unlocks left."
        } catch {
            notice = "That couldn't be saved. Try again."
        }
        if let saved = try? store.load() {
            state = saved
        }
        return false
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
