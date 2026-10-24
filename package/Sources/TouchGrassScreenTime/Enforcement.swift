#if os(iOS)
import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import TouchGrassCore

/// Turns `AppState` into what iOS actually blocks. Called by the app and by the monitor extension
/// whenever Locks change, so both processes always write the same shields.
///
/// Callers apply shields while holding the state file, so shields always match the latest saved
/// state. DeviceActivity bookings happen after letting go: stopping an activity can call back into
/// the monitor extension, which would otherwise wait on a file this process is holding.
public enum Enforcement {
    /// Books the DeviceActivity work that changes shields later: the next wake-up, and one activity
    /// per Schedule and Budget. Call after the state file is released, and off the main thread in
    /// the app, because DeviceActivity calls are synchronous XPC that can take seconds.
    ///
    /// No lock is held while booking: DeviceActivity calls can wait on the monitor extension, which
    /// books too, so a shared lock deadlocks both processes. Instead, if another process saved a
    /// change while this one was booking, it books again, so the last booking matches the saved state.
    public static func scheduleBackgroundWork(using store: AppStateStore, at now: Date = .now) {
        var booked: AppState?
        for _ in 0..<3 {
            guard let state = try? store.load(), state != booked else { return }
            scheduleWakeup(for: state, at: now)
            syncActivities(for: state)
            booked = state
        }
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
    /// iOS delivers that callback when it gets round to it, so a Break can run slightly long.
    ///
    /// Stopping a running activity also calls `intervalDidEnd`, so the booking is left alone when it
    /// already matches, and `wakeupIsDue` lets the monitor tell a real expiry from a cancellation.
    static func scheduleWakeup(for state: AppState, at now: Date) {
        let center = DeviceActivityCenter()
        let next = state.nextEnforcementChange(after: now)
        let booked = bookedWakeup
        if let next, let booked, abs(next.timeIntervalSince(booked)) < 1, center.activities.contains(.wakeup) {
            return
        }

        bookedWakeup = next
        center.stopMonitoring([.wakeup])
        guard let next else { return }

        // DeviceActivity rejects intervals shorter than 15 minutes, so a close wake-up starts in the past.
        let start = min(now, next.addingTimeInterval(-minimumInterval))
        let calendar = Calendar.current
        let components: Set<Calendar.Component> = [.year, .month, .day, .hour, .minute, .second]
        let schedule = DeviceActivitySchedule(
            intervalStart: calendar.dateComponents(components, from: start),
            intervalEnd: calendar.dateComponents(components, from: next),
            repeats: false
        )
        do {
            try center.startMonitoring(.wakeup, during: schedule)
        } catch {
            bookedWakeup = nil
        }
    }

    /// The wake-up that just ended was the booked one reaching its time, not a cancellation.
    public static func wakeupIsDue(at now: Date) -> Bool {
        guard let booked = bookedWakeup else { return false }
        return now >= booked.addingTimeInterval(-60)
    }

    private static var bookedWakeup: Date? {
        get {
            let value = AppGroup.defaults.double(forKey: "wakeup.bookedFor")
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
        set {
            if let newValue {
                AppGroup.defaults.set(newValue.timeIntervalSince1970, forKey: "wakeup.bookedFor")
            } else {
                AppGroup.defaults.removeObject(forKey: "wakeup.bookedFor")
            }
        }
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
