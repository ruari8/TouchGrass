import DeviceActivity
import FamilyControls
import Foundation
import ManagedSettings
import BlockOSDomain

enum BlockOSSharedContainer {
    static let groupIdentifier = "group.pear.BlockOS"
    private static let folderName = "BlockOS"

    static func baseURL() -> URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            return containerURL.appending(path: folderName)
        }

        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: folderName)
    }
}

struct DailyLimitLockState: Codable, Equatable {
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

    static func unlocked(unlockedAt: Date = .now, detail: String? = nil) -> DailyLimitLockState {
        DailyLimitLockState(status: .unlocked, triggeredAt: nil, unlockedAt: unlockedAt, detail: detail)
    }

    var isLocked: Bool {
        status == .locked
    }

    func isUnlockedToday(now: Date = .now, calendar: Calendar = .current) -> Bool {
        guard status == .unlocked, let unlockedAt else {
            return false
        }

        return calendar.isDate(unlockedAt, inSameDayAs: now)
    }
}

enum DailyLimitLockStore {
    private static let fileName = "daily-limit-lock.json"

    static var fileURL: URL {
        BlockOSSharedContainer.baseURL().appending(path: fileName)
    }

    static func load() -> DailyLimitLockState {
        guard
            FileManager.default.fileExists(atPath: fileURL.path),
            let data = try? Data(contentsOf: fileURL),
            let state = try? JSONDecoder().decode(DailyLimitLockState.self, from: data)
        else {
            return .idle
        }

        return state
    }

    static func save(_ state: DailyLimitLockState) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        let data = try encoder.encode(state)
        try data.write(to: fileURL, options: .atomic)
    }
}

final class ScreenTimeDailyLimitMonitor {
    private let center = DeviceActivityCenter()
    private let limitShieldStore = ManagedSettingsStore(named: .blockOSDailyLimit)

    func sync(
        selection: FamilyActivitySelection,
        profile: OnboardingProfile?,
        lockState: DailyLimitLockState
    ) throws -> String {
        guard selection.hasLimitTargets else {
            center.stopMonitoring([.blockOSDailyLimit])
            clearLimitShield()
            try DailyLimitLockStore.save(.idle)
            return "Pick apps or categories to enable the daily limit."
        }

        if lockState.isUnlockedToday() {
            clearLimitShield()
            return "Daily limit reached and unlocked for today."
        }

        let limitMinutes = max(profile?.goalPlan?.idealDailyMinutes ?? 60, 1)
        let event = DeviceActivityEvent(
            applications: selection.applicationTokens,
            categories: selection.categoryTokens,
            webDomains: selection.webDomainTokens,
            threshold: DateComponents(minute: limitMinutes),
            includesPastActivity: true
        )

        try center.startMonitoring(
            .blockOSDailyLimit,
            during: Self.schedule(from: profile?.schedule),
            events: [.blockOSDailyLimitReached: event]
        )

        return "Blocks after \(Self.minutesLabel(limitMinutes)) of selected use each day."
    }

    func clearLimitShield() {
        limitShieldStore.clearAllSettings()
    }

    private static func schedule(from schedule: BlockSchedule?) -> DeviceActivitySchedule {
        guard let schedule else {
            return DeviceActivitySchedule(
                intervalStart: DateComponents(hour: 0, minute: 0),
                intervalEnd: DateComponents(hour: 23, minute: 59),
                repeats: true
            )
        }

        let startHour = min(max(schedule.startHour, 0), 23)
        let endHour = min(max(schedule.endHour, 0), 23)
        let safeEndHour = endHour <= startHour ? 23 : endHour
        let safeEndMinute = endHour <= startHour ? 59 : 0

        return DeviceActivitySchedule(
            intervalStart: DateComponents(hour: startHour, minute: 0),
            intervalEnd: DateComponents(hour: safeEndHour, minute: safeEndMinute),
            repeats: true
        )
    }

    private static func minutesLabel(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }

        if minutes > 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes)m"
    }
}

extension DeviceActivityName {
    static let blockOSDailyLimit = Self("BlockOS.dailyLimit")
}

extension DeviceActivityEvent.Name {
    static let blockOSDailyLimitReached = Self("BlockOS.dailyLimitReached")
}

extension ManagedSettingsStore.Name {
    static let blockOSDailyLimit = Self("BlockOS.dailyLimit")
}

private extension FamilyActivitySelection {
    var hasLimitTargets: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }
}
