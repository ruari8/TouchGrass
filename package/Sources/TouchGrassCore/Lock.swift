import Foundation

/// What started a Lock.
public enum LockSource: Codable, Hashable, Sendable {
    case manual
    case schedule(UUID)
    case budget(UUID)
}

/// A single period of being Locked.
public struct Lock: Codable, Hashable, Identifiable, Sendable {
    public var id: UUID
    public var source: LockSource
    public var blockListID: UUID
    public var startedAt: Date
    /// When the Lock ends on its own. Nil means it lasts until Touch Grass.
    public var endsAt: Date?
    /// While set and in the future, the Lock exists but isn't blocking anything.
    /// A Break pauses until a few minutes from now; dismissing a Schedule or Budget Lock pauses it until `endsAt`.
    public var pausedUntil: Date?

    public init(
        id: UUID = UUID(),
        source: LockSource,
        blockListID: UUID,
        startedAt: Date,
        endsAt: Date? = nil,
        pausedUntil: Date? = nil
    ) {
        self.id = id
        self.source = source
        self.blockListID = blockListID
        self.startedAt = startedAt
        self.endsAt = endsAt
        self.pausedUntil = pausedUntil
    }

    /// The Lock hasn't ended yet.
    public func isActive(at now: Date) -> Bool {
        endsAt.map { now < $0 } ?? true
    }

    /// The Lock is active and its apps are blocked right now.
    public func isEnforced(at now: Date) -> Bool {
        isActive(at: now) && !isPaused(at: now)
    }

    public func isPaused(at now: Date) -> Bool {
        pausedUntil.map { now < $0 } ?? false
    }

    /// Paused for the rest of its run, so it will never block again.
    public func isDismissed(at now: Date) -> Bool {
        guard let pausedUntil, let endsAt else { return false }
        return pausedUntil >= endsAt && isActive(at: now)
    }
}
