#if os(iOS)
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import TouchGrassCore

/// Turns `AppState` into what iOS actually blocks. Called by the app and by the monitor extension
/// whenever Locks change, so both processes always write the same shields.
public enum Enforcement {
    /// Applies the shields for every enforced Lock and books a wake-up for the next time they change on their own.
    public static func sync(_ state: AppState, at now: Date = .now) {
        applyShields(for: state, at: now)
        scheduleWakeup(for: state, at: now)
    }

    public static func applyShields(for state: AppState, at now: Date) {
        let selections = state.enforcedBlockListIDs(at: now)
            .compactMap(state.blockList(id:))
            .map(\.activitySelection)

        let applications = selections.reduce(into: Set<ApplicationToken>()) { $0.formUnion($1.applicationTokens) }
        let categories = selections.reduce(into: Set<ActivityCategoryToken>()) { $0.formUnion($1.categoryTokens) }
        let webDomains = selections.reduce(into: Set<WebDomainToken>()) { $0.formUnion($1.webDomainTokens) }

        let store = ManagedSettingsStore(named: .touchGrass)
        store.shield.applications = applications.isEmpty ? nil : applications
        store.shield.applicationCategories = categories.isEmpty ? nil : .specific(categories)
        store.shield.webDomains = webDomains.isEmpty ? nil : webDomains
        store.shield.webDomainCategories = categories.isEmpty ? nil : .specific(categories)
    }

    /// iOS only runs our code in the background through DeviceActivity, so a Break ending or a
    /// timed Lock ending is booked as a one-off activity whose end wakes the monitor extension.
    static func scheduleWakeup(for state: AppState, at now: Date) {
        let center = DeviceActivityCenter()
        center.stopMonitoring([.wakeup])
        guard let next = state.nextEnforcementChange(after: now) else { return }

        // DeviceActivity rejects intervals shorter than 15 minutes, so a close wake-up starts in the past.
        let start = min(now, next.addingTimeInterval(-minimumInterval))
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: next),
            repeats: false
        )
        try? center.startMonitoring(.wakeup, during: schedule)
    }

    static let minimumInterval: TimeInterval = 15 * 60
}

extension ManagedSettingsStore.Name {
    public static var touchGrass: Self { Self("touchgrass") }
}

extension DeviceActivityName {
    /// A one-off activity that wakes the monitor extension when shields need to change.
    public static var wakeup: Self { Self("touchgrass.wakeup") }
}
#endif
