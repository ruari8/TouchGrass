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
        sync(store.update { state in
            if let id = activity.scheduleID {
                state.startScheduleLock(id: id, at: now)
            } else {
                state.reconcile(at: now)
            }
        }, at: now)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        let now = Date()
        sync(store.update { $0.reconcile(at: now) }, at: now)
    }

    private func sync(_ state: AppState, at now: Date) {
        Enforcement.sync(state, at: now)
        // Waiting rule changes may have just applied.
        Enforcement.syncActivities(for: state)
    }
}
