#if os(iOS)
import DeviceActivity
import Foundation
import TouchGrassCore

extension Enforcement {
    /// Registers one repeating DeviceActivity per enabled Schedule so iOS wakes the monitor
    /// extension when each window opens and closes. Activities that already match are left alone:
    /// restarting one inside its window makes iOS call `intervalDidStart` again, which would loop.
    public static func syncActivities(for state: AppState) {
        let center = DeviceActivityCenter()
        var desired: [DeviceActivityName: DeviceActivitySchedule] = [:]
        for schedule in state.schedules where schedule.isEnabled {
            desired[.schedule(schedule.id)] = DeviceActivitySchedule(
                intervalStart: DateComponents(hour: schedule.start.hour, minute: schedule.start.minute),
                intervalEnd: DateComponents(hour: schedule.end.hour, minute: schedule.end.minute),
                repeats: true
            )
        }

        let stale = center.activities.filter { $0.scheduleID != nil && desired[$0] == nil }
        center.stopMonitoring(stale)

        for (name, schedule) in desired {
            if let existing = center.schedule(for: name),
               existing.intervalStart == schedule.intervalStart,
               existing.intervalEnd == schedule.intervalEnd,
               existing.repeats == schedule.repeats {
                continue
            }
            try? center.startMonitoring(name, during: schedule)
        }
    }
}

extension DeviceActivityName {
    private static let schedulePrefix = "touchgrass.schedule."

    public static func schedule(_ id: UUID) -> Self {
        Self(schedulePrefix + id.uuidString)
    }

    /// The Schedule this activity watches, if it's a Schedule activity.
    public var scheduleID: UUID? {
        guard rawValue.hasPrefix(Self.schedulePrefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(Self.schedulePrefix.count)))
    }
}

extension BlockList {
    /// The new selection still holds every app, category and site the old one did.
    public func covers(_ old: BlockList) -> Bool {
        let new = activitySelection
        let previous = old.activitySelection
        return previous.applicationTokens.isSubset(of: new.applicationTokens)
            && previous.categoryTokens.isSubset(of: new.categoryTokens)
            && previous.webDomainTokens.isSubset(of: new.webDomainTokens)
    }
}
#endif
