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
            state.pruneEndedLocks(at: now)
            state.emergencyUnlocks = state.emergencyUnlocks.merged(with: synced)
        }
    }

    func requestScreenTime() async {
        try? await ScreenTimeAuthorization.request()
        isScreenTimeApproved = ScreenTimeAuthorization.isApproved
    }

    // MARK: Setup

    func completeSetup(blockList: BlockList, style: Style) {
        change { state in
            state.blockLists = [blockList]
            state.settings = .preset(style)
            state.settings.defaultBlockListID = blockList.id
            state.hasCompletedSetup = true
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

    func save(_ blockList: BlockList) {
        changeSettings { state in
            if let index = state.blockLists.firstIndex(where: { $0.id == blockList.id }) {
                state.blockLists[index] = blockList
            } else {
                state.blockLists.append(blockList)
            }
        }
    }

    func deleteBlockList(id: UUID) {
        changeSettings { state in
            guard state.blockLists.count > 1 else { return }
            state.blockLists.removeAll { $0.id == id }
            if state.settings.defaultBlockListID == id {
                state.settings.defaultBlockListID = state.blockLists.first?.id
            }
        }
    }

    func updateSettings(_ body: @escaping (inout Settings) -> Void) {
        changeSettings { body(&$0.settings) }
    }

    // MARK: Private

    /// Rule changes are refused while Locked.
    private func changeSettings(_ body: @escaping (inout AppState) -> Void) {
        let now = Date()
        change(at: now) { state in
            guard !state.hasActiveLocks(at: now) else { return }
            body(&state)
        }
    }

    private func change(at now: Date = .now, _ body: (inout AppState) -> Void) {
        state = store.update(body)
        enforce(at: now)
    }

    private func enforce(at now: Date) {
        Enforcement.sync(state, at: now)
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
