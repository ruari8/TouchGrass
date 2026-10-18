#if os(iOS)
import CryptoKit
import DeviceActivity
import FamilyControls
import Foundation
import TouchGrassCore

/// One repeating DeviceActivity per enabled Budget. Its interval runs from Reset Time to Reset Time,
/// and its single event fires when the Block List's apps reach the Budget's minutes.
enum BudgetActivities {
    static func sync(for state: AppState, center: DeviceActivityCenter) {
        var desired: [DeviceActivityName: Budget] = [:]
        for budget in state.budgets where budget.isEnabled && state.blockList(id: budget.blockListID) != nil {
            desired[.budget(budget.id)] = budget
        }

        let stale = center.activities.filter { $0.budgetID != nil && desired[$0] == nil }
        center.stopMonitoring(stale)
        stale.compactMap(\.budgetID).forEach(Registration.forget)

        for (name, budget) in desired {
            let signature = signature(for: budget, in: state)
            // Restarting an activity mid-interval re-counts today's usage and triggers callbacks,
            // so only restart when something about it has changed.
            if center.activities.contains(name), Registration.signature(for: budget.id) == signature { continue }
            register(budget, in: state, center: center)
        }
    }

    static func register(_ budget: Budget, in state: AppState, center: DeviceActivityCenter) {
        guard let list = state.blockList(id: budget.blockListID) else { return }
        let selection = list.activitySelection
        let reset = state.settings.resetTime
        let lastMinute = (reset.minutesSinceMidnight + 24 * 60 - 1) % (24 * 60)

        let schedule = DeviceActivitySchedule(
            intervalStart: DateComponents(hour: reset.hour, minute: reset.minute),
            intervalEnd: DateComponents(hour: lastMinute / 60, minute: lastMinute % 60, second: 59),
            repeats: true
        )
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: budget.minutes),
            includesPastActivity: true
        )

        let name = DeviceActivityName.budget(budget.id)
        center.stopMonitoring([name])
        do {
            try center.startMonitoring(name, during: schedule, events: [.budgetUsedUp: event])
            Registration.record(budget.id, signature: signature(for: budget, in: state))
        } catch {
            Registration.forget(budget.id)
        }
    }

    private static func signature(for budget: Budget, in state: AppState) -> String {
        var hasher = SHA256()
        hasher.update(data: state.blockList(id: budget.blockListID)?.selection ?? Data())
        hasher.update(data: Data("\(budget.minutes)|\(state.settings.resetTime.minutesSinceMidnight)".utf8))
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension Enforcement {
    /// Whether a Budget's threshold callback should Lock.
    ///
    /// On iOS 26, `eventDidReachThreshold` sometimes fires within seconds of an activity being
    /// registered, before any real usage (Apple forums thread 840907). A callback that soon after
    /// registering is treated as a suspect: the activity is registered again, and the Lock only starts
    /// if that fresh registration fires straight away too, which is what genuine past usage does.
    public static func shouldLockForBudgetThreshold(_ budgetID: UUID, in state: AppState, at now: Date = .now) -> Bool {
        guard let registeredAt = BudgetActivities.Registration.registeredAt(budgetID),
              now.timeIntervalSince(registeredAt) < suspiciousDelay
        else { return true }

        if let suspect = BudgetActivities.Registration.suspectAt(budgetID), now.timeIntervalSince(suspect) < confirmationWindow {
            BudgetActivities.Registration.clearSuspect(budgetID)
            return true
        }

        guard let budget = state.budget(id: budgetID) else { return false }
        BudgetActivities.Registration.markSuspect(budgetID, at: now)
        BudgetActivities.register(budget, in: state, center: DeviceActivityCenter())
        return false
    }

    static let suspiciousDelay: TimeInterval = 10
    static let confirmationWindow: TimeInterval = 120
}

extension BudgetActivities {
    /// When and how each Budget was registered with DeviceActivity, kept in the App Group's defaults
    /// so the app and the monitor extension agree.
    enum Registration {
        private static var defaults: UserDefaults { AppGroup.defaults }

        static func record(_ id: UUID, signature: String) {
            defaults.set(signature, forKey: "budget.signature.\(id)")
            defaults.set(Date().timeIntervalSince1970, forKey: "budget.registeredAt.\(id)")
        }

        static func forget(_ id: UUID) {
            ["signature", "registeredAt", "suspectAt"].forEach { defaults.removeObject(forKey: "budget.\($0).\(id)") }
        }

        static func signature(for id: UUID) -> String? {
            defaults.string(forKey: "budget.signature.\(id)")
        }

        static func registeredAt(_ id: UUID) -> Date? {
            date(forKey: "budget.registeredAt.\(id)")
        }

        static func suspectAt(_ id: UUID) -> Date? {
            date(forKey: "budget.suspectAt.\(id)")
        }

        static func markSuspect(_ id: UUID, at date: Date) {
            defaults.set(date.timeIntervalSince1970, forKey: "budget.suspectAt.\(id)")
        }

        static func clearSuspect(_ id: UUID) {
            defaults.removeObject(forKey: "budget.suspectAt.\(id)")
        }

        private static func date(forKey key: String) -> Date? {
            let value = defaults.double(forKey: key)
            return value > 0 ? Date(timeIntervalSince1970: value) : nil
        }
    }
}

extension DeviceActivityName {
    private static let budgetPrefix = "touchgrass.budget."

    public static func budget(_ id: UUID) -> Self {
        Self(budgetPrefix + id.uuidString)
    }

    /// The Budget this activity watches, if it's a Budget activity.
    public var budgetID: UUID? {
        guard rawValue.hasPrefix(Self.budgetPrefix) else { return nil }
        return UUID(uuidString: String(rawValue.dropFirst(Self.budgetPrefix.count)))
    }
}

extension DeviceActivityEvent.Name {
    public static var budgetUsedUp: Self { Self("touchgrass.budget.usedUp") }
}
#endif
