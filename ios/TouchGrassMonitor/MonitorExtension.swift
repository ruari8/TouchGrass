import DeviceActivity
import Foundation
import TouchGrassCore
import TouchGrassScreenTime

/// Woken by iOS when a DeviceActivity interval starts or ends, so Locks change even while the app is closed.
final class MonitorExtension: DeviceActivityMonitor {
    private let store = AppStateStore()

    override func intervalDidStart(for activity: DeviceActivityName) {
        super.intervalDidStart(for: activity)
        // A wake-up's start is often in the past and fires straight away; only its end matters.
        guard activity != .wakeup else { return }
        let now = Date()
        update(at: now) { state in
            if let id = activity.scheduleID {
                state.startScheduleLock(id: id, at: now)
            } else {
                state.reconcile(at: now)
            }
        }
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let now = Date()
        // Rebooking the wake-up stops the old one, which also lands here.
        if activity == .wakeup, !Enforcement.wakeupIsDue(at: now) { return }
        update(at: now) { $0.reconcile(at: now) }
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        super.eventDidReachThreshold(event, activity: activity)
        guard let id = activity.budgetID, let state = try? store.load() else { return }
        let now = Date()
        guard Enforcement.shouldLockForBudgetThreshold(id, in: state, at: now) else { return }
        update(at: now) { $0.startBudgetLock(id: id, at: now) }
    }

    /// Changes the state and applies its shields while still holding the file, so the app can't
    /// slip a change in between and have its shields overwritten with stale ones.
    private func update(at now: Date, _ change: (inout AppState) -> Void) {
        _ = try? store.update(change) { state in
            Enforcement.sync(state, at: now)
            // Waiting rule changes may have just applied.
            Enforcement.syncActivities(for: state)
        }
    }
}
