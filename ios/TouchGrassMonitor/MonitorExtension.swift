import DeviceActivity
import Foundation
import TouchGrassCore
import TouchGrassScreenTime

/// Woken by iOS when a DeviceActivity interval starts or ends, so Locks change even while the app is closed.
final class MonitorExtension: DeviceActivityMonitor {
    private let store = AppStateStore()

    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        refresh()
    }

    private func refresh() {
        let now = Date()
        let state = store.update { $0.pruneEndedLocks(at: now) }
        Enforcement.sync(state, at: now)
    }
}
