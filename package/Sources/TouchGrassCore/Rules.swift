import Foundation

/// Everything the user configures: Block Lists, Schedules, Budgets and Settings.
public struct Rules: Codable, Hashable, Sendable {
    public var blockLists: [BlockList]
    public var schedules: [Schedule]
    public var budgets: [Budget]
    public var settings: Settings

    public init(blockLists: [BlockList], schedules: [Schedule], budgets: [Budget] = [], settings: Settings) {
        self.blockLists = blockLists
        self.schedules = schedules
        self.budgets = budgets
        self.settings = settings
    }

    /// Schedules plus Budgets, each of which takes one of iOS's DeviceActivity slots.
    public var automaticRuleCount: Int { schedules.count + budgets.count }

    /// Whether moving from `self` to `proposed` would block less in any way.
    /// `listCovers(new, old)` reports whether a Block List's new selection still holds every app the old one did;
    /// Core can't look inside selections, so the Screen Time layer answers that.
    public func isLoosened(by proposed: Rules, listCovers: (BlockList, BlockList) -> Bool) -> Bool {
        settings.isLoosened(by: proposed.settings)
            || defaultListIsLoosened(by: proposed, listCovers: listCovers)
            || blockLists.contains { old in
                guard let new = proposed.blockLists.first(where: { $0.id == old.id }) else { return true }
                return !listCovers(new, old)
            }
            || schedules.contains { old in
                guard old.isEnabled else { return false }
                guard let new = proposed.schedules.first(where: { $0.id == old.id }) else { return true }
                return new.blockListID != old.blockListID || !new.covers(old)
            }
            || budgets.contains { old in
                guard old.isEnabled else { return false }
                guard let new = proposed.budgets.first(where: { $0.id == old.id }) else { return true }
                return !new.isEnabled || new.blockListID != old.blockListID || new.minutes > old.minutes
            }
    }
}

extension Rules {
    var defaultBlockList: BlockList? {
        settings.defaultBlockListID.flatMap { id in blockLists.first { $0.id == id } } ?? blockLists.first
    }

    /// A Manual Lock that would lock fewer apps than before.
    private func defaultListIsLoosened(by proposed: Rules, listCovers: (BlockList, BlockList) -> Bool) -> Bool {
        guard let old = defaultBlockList else { return false }
        guard let new = proposed.defaultBlockList else { return true }
        return !listCovers(new, old)
    }
}

extension Settings {
    func isLoosened(by proposed: Settings) -> Bool {
        (!manualLocksCanHaveDuration && proposed.manualLocksCanHaveDuration)
            || (touchGrassGivesBreak && !proposed.touchGrassGivesBreak)
            || (touchGrassGivesBreak && proposed.breakMinutes > breakMinutes)
            || (looseningWaitsUntilTomorrow && !proposed.looseningWaitsUntilTomorrow)
            // Moving the Reset Time could refill a Budget early.
            || resetTime != proposed.resetTime
    }
}

/// Rule changes that loosen things in Strict, waiting for the next Reset Time.
public struct PendingRules: Codable, Hashable, Sendable {
    public var rules: Rules
    public var appliesAt: Date

    public init(rules: Rules, appliesAt: Date) {
        self.rules = rules
        self.appliesAt = appliesAt
    }
}

/// What happened to a requested rule change.
public enum RuleChangeOutcome: Equatable, Sendable {
    case applied
    case waitingUntil(Date)
    /// Rules are frozen while any Lock is active.
    case refusedWhileLocked
}

extension AppState {
    public var rules: Rules {
        get { Rules(blockLists: blockLists, schedules: schedules, budgets: budgets, settings: settings) }
        set {
            blockLists = newValue.blockLists
            schedules = newValue.schedules
            budgets = newValue.budgets
            settings = newValue.settings
        }
    }

    /// The rules as they will be once any waiting changes apply. Editors start from these.
    public var upcomingRules: Rules {
        pendingRules?.rules ?? rules
    }

    /// Changes the rules. Tightening applies at once. Loosening waits for the next Reset Time
    /// when `looseningWaitsUntilTomorrow` is on. Nothing changes while a Lock is active.
    ///
    /// The change is applied to the upcoming rules (which include anything already waiting). If that
    /// loosens the current rules but the same change on its own doesn't, it applies now as well,
    /// so adding a Schedule takes effect at once even while a loosening change is waiting.
    @discardableResult
    public mutating func changeRules(
        at now: Date,
        calendar: Calendar = .current,
        listCovers: (BlockList, BlockList) -> Bool,
        _ change: (inout Rules) -> Void
    ) -> RuleChangeOutcome {
        guard !hasActiveLocks(at: now) else { return .refusedWhileLocked }
        var proposed = upcomingRules
        change(&proposed)
        proposed.normalise()

        guard settings.looseningWaitsUntilTomorrow, rules.isLoosened(by: proposed, listCovers: listCovers) else {
            rules = proposed
            pendingRules = nil
            return .applied
        }

        let appliesAt = settings.resetTime.next(after: now, calendar: calendar)
        let wasWaiting = pendingRules != nil
        pendingRules = PendingRules(rules: proposed, appliesAt: appliesAt)

        var immediate = rules
        change(&immediate)
        immediate.normalise()
        if wasWaiting, !rules.isLoosened(by: immediate, listCovers: listCovers) {
            rules = immediate
            return .applied
        }
        return .waitingUntil(appliesAt)
    }

    /// Drops waiting changes, keeping the current rules. Like every rule change, refused while Locked.
    @discardableResult
    public mutating func cancelPendingRules(at now: Date) -> RuleChangeOutcome {
        guard !hasActiveLocks(at: now) else { return .refusedWhileLocked }
        pendingRules = nil
        return .applied
    }

    /// Applies waiting changes once their Reset Time has passed and no Lock is active,
    /// so a loosening never cuts a running Lock short.
    public mutating func applyPendingRules(at now: Date) {
        guard let pendingRules, now >= pendingRules.appliesAt, !hasActiveLocks(at: now) else { return }
        rules = pendingRules.rules
        self.pendingRules = nil
    }
}

extension Rules {
    /// Keeps references valid after Block Lists are deleted.
    mutating func normalise() {
        let ids = Set(blockLists.map(\.id))
        schedules.removeAll { !ids.contains($0.blockListID) }
        budgets.removeAll { !ids.contains($0.blockListID) }
        if let id = settings.defaultBlockListID, !ids.contains(id) {
            settings.defaultBlockListID = blockLists.first?.id
        }
    }
}
