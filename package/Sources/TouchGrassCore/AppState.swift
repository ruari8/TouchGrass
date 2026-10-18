import Foundation

/// Everything Touch Grass remembers, shared between the app and its extensions through the App Group.
public struct AppState: Codable, Hashable, Sendable {
    public var hasCompletedSetup: Bool
    public var blockLists: [BlockList]
    public var schedules: [Schedule]
    public var budgets: [Budget]
    public var settings: Settings
    /// Loosening changes waiting for the next Reset Time.
    public var pendingRules: PendingRules?
    public var locks: [Lock]
    /// The running total of times the user has touched grass.
    public var grassCount: Int
    public var emergencyUnlocks: EmergencyUnlockLedger

    public init(
        hasCompletedSetup: Bool = false,
        blockLists: [BlockList] = [],
        schedules: [Schedule] = [],
        budgets: [Budget] = [],
        settings: Settings = .preset(.strict),
        pendingRules: PendingRules? = nil,
        locks: [Lock] = [],
        grassCount: Int = 0,
        emergencyUnlocks: EmergencyUnlockLedger = EmergencyUnlockLedger()
    ) {
        self.hasCompletedSetup = hasCompletedSetup
        self.blockLists = blockLists
        self.schedules = schedules
        self.budgets = budgets
        self.settings = settings
        self.pendingRules = pendingRules
        self.locks = locks
        self.grassCount = grassCount
        self.emergencyUnlocks = emergencyUnlocks
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AppState()
        hasCompletedSetup = try container.decodeIfPresent(Bool.self, forKey: .hasCompletedSetup) ?? defaults.hasCompletedSetup
        blockLists = try container.decodeIfPresent([BlockList].self, forKey: .blockLists) ?? defaults.blockLists
        schedules = try container.decodeIfPresent([Schedule].self, forKey: .schedules) ?? defaults.schedules
        budgets = try container.decodeIfPresent([Budget].self, forKey: .budgets) ?? defaults.budgets
        settings = try container.decodeIfPresent(Settings.self, forKey: .settings) ?? defaults.settings
        pendingRules = try container.decodeIfPresent(PendingRules.self, forKey: .pendingRules)
        locks = try container.decodeIfPresent([Lock].self, forKey: .locks) ?? defaults.locks
        grassCount = try container.decodeIfPresent(Int.self, forKey: .grassCount) ?? defaults.grassCount
        emergencyUnlocks = try container.decodeIfPresent(EmergencyUnlockLedger.self, forKey: .emergencyUnlocks) ?? defaults.emergencyUnlocks
    }

    public func blockList(id: UUID) -> BlockList? {
        blockLists.first { $0.id == id }
    }

    public func schedule(id: UUID) -> Schedule? {
        schedules.first { $0.id == id }
    }

    public var defaultBlockList: BlockList? {
        settings.defaultBlockListID.flatMap(blockList(id:)) ?? blockLists.first
    }
}
