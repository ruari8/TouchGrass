import Foundation

/// Tracks Emergency Unlocks. A user starts with 3 and holds at most 3; each one used comes back 30 days later.
public struct EmergencyUnlockLedger: Codable, Hashable, Sendable {
    public static let maximum = 3
    public static let refillInterval: TimeInterval = 30 * 24 * 60 * 60

    /// When each Emergency Unlock still on its 30-day refill was used.
    public private(set) var usedAt: [Date]

    public init(usedAt: [Date] = []) {
        self.usedAt = usedAt.sorted()
    }

    public func available(at now: Date) -> Int {
        Self.maximum - outstanding(at: now).count
    }

    /// When the next used Emergency Unlock comes back, if any are refilling.
    public func nextRefill(at now: Date) -> Date? {
        outstanding(at: now).first.map { $0.addingTimeInterval(Self.refillInterval) }
    }

    public mutating func use(at now: Date) throws(EmergencyUnlockError) {
        guard available(at: now) > 0 else { throw .noneLeft }
        usedAt = outstanding(at: now) + [now]
    }

    /// Combines uses recorded on another device or install, so deleting the app doesn't refill them.
    public func merged(with other: EmergencyUnlockLedger) -> EmergencyUnlockLedger {
        EmergencyUnlockLedger(usedAt: Array(Set(usedAt + other.usedAt)))
    }

    private func outstanding(at now: Date) -> [Date] {
        usedAt.filter { now < $0.addingTimeInterval(Self.refillInterval) }
    }
}

public enum EmergencyUnlockError: Error, Equatable {
    case noneLeft
}
