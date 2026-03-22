import DeviceActivity
import ExtensionKit
import Foundation
import SwiftUI

extension DeviceActivityReport.Context {
    static let blockOSOnboarding = Self("BlockOS Onboarding")
}

struct OnboardingUsageSummary {
    struct AppUsage: Hashable {
        let name: String
        let durationText: String
    }

    let averageDailyText: String
    let weeklyTotalText: String
    let topApps: [AppUsage]
    let hasData: Bool
}

struct OnboardingUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .blockOSOnboarding
    let content: (OnboardingUsageSummary) -> OnboardingUsageSummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> OnboardingUsageSummary {
        var totalActivityDuration: TimeInterval = 0
        var segmentCount = 0
        var appTotals: [String: TimeInterval] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                totalActivityDuration += segment.totalActivityDuration
                segmentCount += 1

                for await category in segment.categories {
                    for await application in category.applications {
                        let name = application.application.localizedDisplayName
                            ?? application.application.bundleIdentifier
                            ?? "Unknown App"
                        appTotals[name, default: 0] += application.totalActivityDuration
                    }
                }
            }
        }

        guard totalActivityDuration > 0 else {
            return OnboardingUsageSummary(
                averageDailyText: "No recent data",
                weeklyTotalText: "Open your usual apps for a day or two, then revisit this setup.",
                topApps: [],
                hasData: false
            )
        }

        let averageDaily = totalActivityDuration / Double(max(segmentCount, 1))
        let topApps = appTotals
            .sorted { $0.value > $1.value }
            .prefix(3)
            .map { entry in
                OnboardingUsageSummary.AppUsage(
                    name: entry.key,
                    durationText: formatDuration(entry.value)
                )
            }

        return OnboardingUsageSummary(
            averageDailyText: formatDuration(averageDaily),
            weeklyTotalText: formatDuration(totalActivityDuration),
            topApps: Array(topApps),
            hasData: true
        )
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: duration) ?? "0m"
    }
}
