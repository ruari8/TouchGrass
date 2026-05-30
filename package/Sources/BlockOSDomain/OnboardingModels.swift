import Foundation

public enum OnboardingFeeling: String, Codable, CaseIterable, Sendable {
    case okay
    case concerned
    case frustrated
    case overwhelmed
}

public struct ScreenTimeCategoryBudget: Codable, Hashable, Sendable {
    public var categoryKey: String
    public var displayName: String
    public var minutes: Int

    public init(categoryKey: String, displayName: String, minutes: Int) {
        self.categoryKey = categoryKey
        self.displayName = displayName
        self.minutes = minutes
    }
}

public struct ScreenTimeGoalPlan: Codable, Hashable, Sendable {
    public var reductionFocus: String
    public var idealDailyMinutes: Int
    public var socialMediaMinutes: Int
    public var everythingElseMinutes: Int
    public var categoryBudgets: [ScreenTimeCategoryBudget]

    private enum CodingKeys: String, CodingKey {
        case reductionFocus
        case idealDailyMinutes
        case socialMediaMinutes
        case everythingElseMinutes
        case categoryBudgets
    }

    public init(
        reductionFocus: String,
        idealDailyMinutes: Int,
        socialMediaMinutes: Int,
        everythingElseMinutes: Int,
        categoryBudgets: [ScreenTimeCategoryBudget] = []
    ) {
        self.reductionFocus = reductionFocus
        self.idealDailyMinutes = idealDailyMinutes
        self.socialMediaMinutes = socialMediaMinutes
        self.everythingElseMinutes = everythingElseMinutes
        self.categoryBudgets = categoryBudgets
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        reductionFocus = try container.decode(String.self, forKey: .reductionFocus)
        idealDailyMinutes = try container.decode(Int.self, forKey: .idealDailyMinutes)
        socialMediaMinutes = try container.decodeIfPresent(Int.self, forKey: .socialMediaMinutes) ?? 0
        everythingElseMinutes = try container.decodeIfPresent(Int.self, forKey: .everythingElseMinutes)
            ?? max(idealDailyMinutes - socialMediaMinutes, 0)
        categoryBudgets = try container.decodeIfPresent([ScreenTimeCategoryBudget].self, forKey: .categoryBudgets) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(reductionFocus, forKey: .reductionFocus)
        try container.encode(idealDailyMinutes, forKey: .idealDailyMinutes)
        try container.encode(socialMediaMinutes, forKey: .socialMediaMinutes)
        try container.encode(everythingElseMinutes, forKey: .everythingElseMinutes)
        try container.encode(categoryBudgets, forKey: .categoryBudgets)
    }
}

/// A time-of-day window during which daily limit monitoring should be active.
/// Hours are in 24-hour format (0–23). `nil` schedule means all day.
public struct BlockSchedule: Codable, Hashable, Sendable {
    public var startHour: Int
    public var endHour: Int

    public static let workHours = BlockSchedule(startHour: 9, endHour: 18)
    public static let evenings  = BlockSchedule(startHour: 18, endHour: 23)
    public static let mornings  = BlockSchedule(startHour: 6, endHour: 12)

    public var displayText: String { "\(formatHour(startHour)) – \(formatHour(endHour))" }

    private func formatHour(_ h: Int) -> String {
        let period = h < 12 ? "am" : "pm"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display)\(period)"
    }

    public init(startHour: Int, endHour: Int) {
        self.startHour = startHour
        self.endHour = endHour
    }
}

public struct OnboardingProfile: Codable, Hashable, Sendable {
    public var completedAt: Date
    public var skippedIntake: Bool
    public var feeling: OnboardingFeeling?
    public var goalPlan: ScreenTimeGoalPlan?
    public var schedule: BlockSchedule?

    public init(
        completedAt: Date = .now,
        skippedIntake: Bool,
        feeling: OnboardingFeeling? = nil,
        goalPlan: ScreenTimeGoalPlan? = nil,
        schedule: BlockSchedule? = nil
    ) {
        self.completedAt = completedAt
        self.skippedIntake = skippedIntake
        self.feeling = feeling
        self.goalPlan = goalPlan
        self.schedule = schedule
    }
}
