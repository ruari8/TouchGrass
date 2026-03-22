import Foundation

public enum OnboardingFeeling: String, Codable, CaseIterable, Sendable {
    case okay
    case concerned
    case frustrated
    case overwhelmed
}

public struct ScreenTimeGoalPlan: Codable, Hashable, Sendable {
    public var reductionFocus: String
    public var idealDailyMinutes: Int
    public var socialMediaMinutes: Int
    public var everythingElseMinutes: Int

    public init(
        reductionFocus: String,
        idealDailyMinutes: Int,
        socialMediaMinutes: Int,
        everythingElseMinutes: Int
    ) {
        self.reductionFocus = reductionFocus
        self.idealDailyMinutes = idealDailyMinutes
        self.socialMediaMinutes = socialMediaMinutes
        self.everythingElseMinutes = everythingElseMinutes
    }
}

public struct OnboardingProfile: Codable, Hashable, Sendable {
    public var completedAt: Date
    public var skippedIntake: Bool
    public var feeling: OnboardingFeeling?
    public var goalPlan: ScreenTimeGoalPlan?

    public init(
        completedAt: Date = .now,
        skippedIntake: Bool,
        feeling: OnboardingFeeling? = nil,
        goalPlan: ScreenTimeGoalPlan? = nil
    ) {
        self.completedAt = completedAt
        self.skippedIntake = skippedIntake
        self.feeling = feeling
        self.goalPlan = goalPlan
    }
}
