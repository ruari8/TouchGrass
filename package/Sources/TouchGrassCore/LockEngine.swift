import Foundation

/// The rules for getting Locked and getting out.
extension AppState {
    /// The phone is Locked: at least one Lock is blocking apps right now.
    public func isLocked(at now: Date) -> Bool {
        locks.contains { $0.isEnforced(at: now) }
    }

    /// At least one Lock hasn't ended, even if it's paused for a Break.
    /// Settings stay frozen while this is true.
    public func hasActiveLocks(at now: Date) -> Bool {
        locks.contains { $0.isActive(at: now) && !$0.isDismissed(at: now) }
    }

    public func activeLocks(at now: Date) -> [Lock] {
        locks.filter { $0.isActive(at: now) && !$0.isDismissed(at: now) }
    }

    /// The Block Lists whose apps are blocked right now.
    public func enforcedBlockListIDs(at now: Date) -> Set<UUID> {
        Set(locks.filter { $0.isEnforced(at: now) }.map(\.blockListID))
    }

    /// When the current Break ends, if every active Lock is paused.
    public func breakEnds(at now: Date) -> Date? {
        let active = activeLocks(at: now)
        guard !active.isEmpty, active.allSatisfy({ $0.isPaused(at: now) }) else { return nil }
        return active.compactMap(\.pausedUntil).min()
    }

    /// The next moment the set of blocked apps changes on its own: a Break ending or a Lock ending.
    public func nextEnforcementChange(after now: Date) -> Date? {
        locks
            .flatMap { [$0.pausedUntil, $0.endsAt] }
            .compactMap { $0 }
            .filter { $0 > now }
            .min()
    }

    /// Starts a Manual Lock. Locking a Block List that is already manually Locked does nothing.
    @discardableResult
    public mutating func startManualLock(blockListID: UUID, endsAt: Date? = nil, at now: Date) -> Lock? {
        guard blockList(id: blockListID) != nil else { return nil }
        if let existing = locks.first(where: { $0.source == .manual && $0.blockListID == blockListID && $0.isEnforced(at: now) }) {
            return existing
        }
        let lock = Lock(source: .manual, blockListID: blockListID, startedAt: now, endsAt: endsAt)
        locks.append(lock)
        return lock
    }

    /// Starts a Lock from a Schedule or Budget. Starting the same source twice in one run does nothing,
    /// so a Lock that was dismissed with Touch Grass isn't brought back by a repeated trigger.
    @discardableResult
    public mutating func startAutomaticLock(source: LockSource, blockListID: UUID, endsAt: Date, at now: Date) -> Lock? {
        guard source != .manual, blockList(id: blockListID) != nil, now < endsAt else { return nil }
        if let existing = locks.first(where: { $0.source == source && $0.isActive(at: now) }) {
            return existing
        }
        let lock = Lock(source: source, blockListID: blockListID, startedAt: now, endsAt: endsAt)
        locks.append(lock)
        return lock
    }

    /// Ends a Schedule or Budget Lock early, for example when its Schedule is deleted.
    public mutating func endLocks(from source: LockSource) {
        locks.removeAll { $0.source == source }
    }

    /// One Touch Grass applies to every active Lock at once.
    /// It ends Manual Locks. Schedule and Budget Locks get a Break in Strict and are dismissed in Flexible.
    public mutating func touchGrass(at now: Date) {
        grassCount += 1
        let breakEnd = now.addingTimeInterval(TimeInterval(settings.breakMinutes * 60))
        let givesBreak = settings.touchGrassGivesBreak
        release(at: now) { lock in
            givesBreak ? breakEnd : lock.endsAt
        }
    }

    /// Ends every active Lock completely, without Touching Grass.
    public mutating func useEmergencyUnlock(at now: Date) throws(EmergencyUnlockError) {
        try emergencyUnlocks.use(at: now)
        release(at: now) { $0.endsAt }
    }

    /// Forgets Locks that have ended.
    public mutating func pruneEndedLocks(at now: Date) {
        locks.removeAll { !$0.isActive(at: now) }
    }

    private mutating func release(at now: Date, pauseUntil: (Lock) -> Date?) {
        pruneEndedLocks(at: now)
        locks = locks.compactMap { lock in
            guard lock.source != .manual, let endsAt = lock.endsAt, let pause = pauseUntil(lock) else { return nil }
            var paused = lock
            paused.pausedUntil = max(min(pause, endsAt), lock.pausedUntil ?? .distantPast)
            return paused
        }
    }
}
