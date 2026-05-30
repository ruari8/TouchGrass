import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings

final class DailyLimitMonitorExtension: DeviceActivityMonitor {
    private let limitShieldStore = ManagedSettingsStore(named: .blockOSDailyLimit)

    override func intervalDidStart(for activity: DeviceActivityName) {
        guard activity == .blockOSDailyLimit else {
            return
        }

        limitShieldStore.clearAllSettings()
        try? DailyLimitLockStore.save(.idle)
    }

    override func intervalDidEnd(for activity: DeviceActivityName) {
        guard activity == .blockOSDailyLimit else {
            return
        }

        limitShieldStore.clearAllSettings()
        try? DailyLimitLockStore.save(.idle)
    }

    override func eventDidReachThreshold(_ event: DeviceActivityEvent.Name, activity: DeviceActivityName) {
        guard activity == .blockOSDailyLimit, event == .blockOSDailyLimitReached else {
            return
        }

        guard let selection = try? FamilyActivitySelectionDiskStore.load(), selection.hasLimitTargets else {
            return
        }

        limitShieldStore.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        limitShieldStore.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        limitShieldStore.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens

        try? DailyLimitLockStore.save(
            .locked(detail: "Daily selected-use threshold reached.")
        )
    }
}

private enum BlockOSSharedContainer {
    static let groupIdentifier = "group.pear.BlockOS"
    private static let folderName = "BlockOS"

    static func baseURL() -> URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)?
            .appending(path: folderName)
    }
}

private enum FamilyActivitySelectionDiskStore {
    private static let fileName = "activity-selection.json"

    static func load() throws -> FamilyActivitySelection {
        guard let baseURL = BlockOSSharedContainer.baseURL() else {
            return FamilyActivitySelection()
        }

        let fileURL = baseURL.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return FamilyActivitySelection()
        }

        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(FamilyActivitySelection.self, from: data)
    }
}

private struct DailyLimitLockState: Codable {
    enum Status: String, Codable {
        case idle
        case locked
        case unlocked
    }

    var status: Status
    var triggeredAt: Date?
    var unlockedAt: Date?
    var detail: String?

    static let idle = DailyLimitLockState(status: .idle, triggeredAt: nil, unlockedAt: nil, detail: nil)

    static func locked(triggeredAt: Date = .now, detail: String? = nil) -> DailyLimitLockState {
        DailyLimitLockState(status: .locked, triggeredAt: triggeredAt, unlockedAt: nil, detail: detail)
    }
}

private enum DailyLimitLockStore {
    private static let fileName = "daily-limit-lock.json"

    static func save(_ state: DailyLimitLockState) throws {
        guard let baseURL = BlockOSSharedContainer.baseURL() else {
            return
        }

        try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(state)
        try data.write(to: baseURL.appending(path: fileName), options: .atomic)
    }
}

private extension FamilyActivitySelection {
    var hasLimitTargets: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }
}

private extension DeviceActivityName {
    static let blockOSDailyLimit = Self("BlockOS.dailyLimit")
}

private extension DeviceActivityEvent.Name {
    static let blockOSDailyLimitReached = Self("BlockOS.dailyLimitReached")
}

private extension ManagedSettingsStore.Name {
    static let blockOSDailyLimit = Self("BlockOS.dailyLimit")
}
