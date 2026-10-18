import Foundation

/// A daily allowance of minutes for the apps on a Block List. Once it's used up, a Lock starts
/// and lasts until the next Reset Time.
public struct Budget: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    public var blockListID: UUID
    public var minutes: Int
    public var isEnabled: Bool

    public init(id: UUID = UUID(), name: String, blockListID: UUID, minutes: Int, isEnabled: Bool = true) {
        self.id = id
        self.name = name
        self.blockListID = blockListID
        self.minutes = minutes
        self.isEnabled = isEnabled
    }

    public static let minuteOptions = Array(stride(from: 15, through: 12 * 60, by: 15))
}

extension AppState {
    public func budget(id: UUID) -> Budget? {
        budgets.first { $0.id == id }
    }

    /// The current Budget day: from the last Reset Time to the next one.
    public func budgetDay(containing now: Date, calendar: Calendar = .current) -> DateInterval {
        let next = settings.resetTime.next(after: now, calendar: calendar)
        let start = calendar.date(byAdding: .day, value: -1, to: next) ?? next.addingTimeInterval(-24 * 60 * 60)
        return DateInterval(start: start, end: next)
    }

    /// Starts a Budget's Lock once iOS reports its minutes are used up. The Lock lasts until the next Reset Time.
    public mutating func startBudgetLock(id: UUID, at now: Date, calendar: Calendar = .current) {
        reconcile(at: now, calendar: calendar)
        guard let budget = budget(id: id), budget.isEnabled else { return }
        startAutomaticLock(
            source: .budget(id),
            blockListID: budget.blockListID,
            endsAt: budgetDay(containing: now, calendar: calendar).end,
            at: now
        )
    }
}
