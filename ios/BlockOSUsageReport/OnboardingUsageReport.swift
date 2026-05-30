import DeviceActivity
import ExtensionKit
import Foundation
import SwiftUI
import UniformTypeIdentifiers

extension DeviceActivityReport.Context {
    static let blockOSOnboarding = Self("BlockOS Onboarding")
}

struct OnboardingUsageSummary: Codable, Hashable {
    struct AppUsage: Codable, Hashable {
        let id: String
        let title: String
        let dailyAverageMinutes: Int
        let dailyAverageText: String
        let weeklyTotalText: String
        let shareOfCategory: Double
    }

    struct CategoryUsage: Codable, Hashable {
        let id: String
        let title: String
        let icon: String
        let dailyAverageMinutes: Int
        let dailyAverageText: String
        let weeklyTotalText: String
        let recommendedMinutes: Int
        let recommendedText: String
        let shareOfTotal: Double
        let apps: [AppUsage]

        private enum CodingKeys: String, CodingKey {
            case id
            case title
            case icon
            case dailyAverageMinutes
            case dailyAverageText
            case weeklyTotalText
            case recommendedMinutes
            case recommendedText
            case shareOfTotal
            case apps
        }

        init(
            id: String,
            title: String,
            icon: String,
            dailyAverageMinutes: Int,
            dailyAverageText: String,
            weeklyTotalText: String,
            recommendedMinutes: Int,
            recommendedText: String,
            shareOfTotal: Double,
            apps: [AppUsage]
        ) {
            self.id = id
            self.title = title
            self.icon = icon
            self.dailyAverageMinutes = dailyAverageMinutes
            self.dailyAverageText = dailyAverageText
            self.weeklyTotalText = weeklyTotalText
            self.recommendedMinutes = recommendedMinutes
            self.recommendedText = recommendedText
            self.shareOfTotal = shareOfTotal
            self.apps = apps
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decode(String.self, forKey: .id)
            title = try container.decode(String.self, forKey: .title)
            icon = try container.decode(String.self, forKey: .icon)
            dailyAverageMinutes = try container.decode(Int.self, forKey: .dailyAverageMinutes)
            dailyAverageText = try container.decode(String.self, forKey: .dailyAverageText)
            weeklyTotalText = try container.decode(String.self, forKey: .weeklyTotalText)
            recommendedMinutes = try container.decode(Int.self, forKey: .recommendedMinutes)
            recommendedText = try container.decode(String.self, forKey: .recommendedText)
            shareOfTotal = try container.decode(Double.self, forKey: .shareOfTotal)
            apps = try container.decodeIfPresent([AppUsage].self, forKey: .apps) ?? []
        }
    }

    struct PlanRow: Codable, Hashable {
        let id: String
        let title: String
        let icon: String
        let currentAverageMinutes: Int
        let currentAverageText: String
        let targetMinutes: Int
        let targetText: String
    }

    let averageDailyMinutes: Int
    let averageDailyText: String
    let weeklyTotalText: String
    let recommendedDailyMinutes: Int
    let recommendedDailyText: String
    let categories: [CategoryUsage]
    let planRows: [PlanRow]
    let hasData: Bool
    let daysTracked: Int
}

struct OnboardingUsageReport: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .blockOSOnboarding
    let content: (OnboardingUsageSummary) -> OnboardingUsageSummaryView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> OnboardingUsageSummary {
        var totalActivityDuration: TimeInterval = 0
        var segmentCount = 0
        var categoryTotals: [String: CategoryAccumulator] = [:]

        for await activityData in data {
            for await segment in activityData.activitySegments {
                totalActivityDuration += segment.totalActivityDuration
                segmentCount += 1

                for await category in segment.categories {
                    let title = normalizedCategoryTitle(from: category.category.localizedDisplayName)
                    let id = categoryIdentifier(for: title)
                    let style = categoryStyle(for: title)

                    if var accumulator = categoryTotals[id] {
                        accumulator.weeklyTotal += category.totalActivityDuration

                        for await application in category.applications {
                            let appTitle = normalizedAppTitle(
                                from: application.application.localizedDisplayName,
                                bundleIdentifier: application.application.bundleIdentifier
                            )
                            let appID = applicationIdentifier(
                                bundleIdentifier: application.application.bundleIdentifier,
                                title: appTitle
                            )

                            if var appAccumulator = accumulator.applications[appID] {
                                appAccumulator.weeklyTotal += application.totalActivityDuration
                                accumulator.applications[appID] = appAccumulator
                            } else {
                                accumulator.applications[appID] = AppAccumulator(
                                    id: appID,
                                    title: appTitle,
                                    weeklyTotal: application.totalActivityDuration
                                )
                            }
                        }

                        categoryTotals[id] = accumulator
                    } else {
                        var accumulator = CategoryAccumulator(
                            id: id,
                            title: title,
                            icon: style.icon,
                            reductionFactor: style.reductionFactor,
                            minimumFloor: style.minimumFloor,
                            weeklyTotal: category.totalActivityDuration,
                            applications: [:]
                        )

                        for await application in category.applications {
                            let appTitle = normalizedAppTitle(
                                from: application.application.localizedDisplayName,
                                bundleIdentifier: application.application.bundleIdentifier
                            )
                            let appID = applicationIdentifier(
                                bundleIdentifier: application.application.bundleIdentifier,
                                title: appTitle
                            )

                            accumulator.applications[appID] = AppAccumulator(
                                id: appID,
                                title: appTitle,
                                weeklyTotal: application.totalActivityDuration
                            )
                        }

                        categoryTotals[id] = accumulator
                    }
                }
            }
        }

        guard totalActivityDuration > 0 else {
            let emptySummary = OnboardingUsageSummary(
                averageDailyMinutes: 0,
                averageDailyText: "No recent data",
                weeklyTotalText: "Open your usual apps for a day or two, then revisit this setup.",
                recommendedDailyMinutes: 0,
                recommendedDailyText: "No target yet",
                categories: [],
                planRows: [],
                hasData: false,
                daysTracked: 0
            )

            SharedOnboardingUsageSummaryCache.save(emptySummary)
            return emptySummary
        }

        let daysTracked = max(segmentCount, 1)
        let averageDailyDuration = totalActivityDuration / Double(daysTracked)
        let averageDailyMinutes = max(Int(averageDailyDuration / 60), 0)

        let categories = categoryTotals.values
            .map { accumulator -> OnboardingUsageSummary.CategoryUsage in
                let dailyAverageMinutes = max(Int((accumulator.weeklyTotal / Double(daysTracked)) / 60), 0)
                let recommendedMinutes = recommendedMinutes(
                    currentDailyMinutes: dailyAverageMinutes,
                    reductionFactor: accumulator.reductionFactor,
                    minimumFloor: accumulator.minimumFloor
                )
                let apps = accumulator.applications.values
                    .map { app in
                        let appDailyAverageMinutes = max(Int((app.weeklyTotal / Double(daysTracked)) / 60), 0)
                        return OnboardingUsageSummary.AppUsage(
                            id: app.id,
                            title: app.title,
                            dailyAverageMinutes: appDailyAverageMinutes,
                            dailyAverageText: formatDuration(minutes: appDailyAverageMinutes),
                            weeklyTotalText: formatDuration(app.weeklyTotal),
                            shareOfCategory: accumulator.weeklyTotal == 0 ? 0 : app.weeklyTotal / accumulator.weeklyTotal
                        )
                    }
                    .sorted {
                        if $0.dailyAverageMinutes == $1.dailyAverageMinutes {
                            return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                        }
                        return $0.dailyAverageMinutes > $1.dailyAverageMinutes
                    }

                return OnboardingUsageSummary.CategoryUsage(
                    id: accumulator.id,
                    title: accumulator.title,
                    icon: accumulator.icon,
                    dailyAverageMinutes: dailyAverageMinutes,
                    dailyAverageText: formatDuration(minutes: dailyAverageMinutes),
                    weeklyTotalText: formatDuration(accumulator.weeklyTotal),
                    recommendedMinutes: recommendedMinutes,
                    recommendedText: formatDuration(minutes: recommendedMinutes),
                    shareOfTotal: averageDailyMinutes == 0 ? 0 : Double(dailyAverageMinutes) / Double(averageDailyMinutes),
                    apps: apps
                )
            }
            .sorted {
                if $0.dailyAverageMinutes == $1.dailyAverageMinutes {
                    return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
                }
                return $0.dailyAverageMinutes > $1.dailyAverageMinutes
            }

        let planRows = categories.map { category in
            OnboardingUsageSummary.PlanRow(
                id: category.id,
                title: category.title,
                icon: category.icon,
                currentAverageMinutes: category.dailyAverageMinutes,
                currentAverageText: category.dailyAverageText,
                targetMinutes: category.recommendedMinutes,
                targetText: category.recommendedText
            )
        }
        let recommendedDailyMinutes = planRows.reduce(0) { $0 + $1.targetMinutes }

        let summary = OnboardingUsageSummary(
            averageDailyMinutes: averageDailyMinutes,
            averageDailyText: formatDuration(averageDailyDuration),
            weeklyTotalText: formatDuration(totalActivityDuration),
            recommendedDailyMinutes: recommendedDailyMinutes,
            recommendedDailyText: formatDuration(minutes: recommendedDailyMinutes),
            categories: categories,
            planRows: planRows,
            hasData: true,
            daysTracked: daysTracked
        )

        SharedOnboardingUsageSummaryCache.save(summary)
        return summary
    }

    private func normalizedCategoryTitle(from localizedDisplayName: String?) -> String {
        let trimmed = localizedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Other" : trimmed
    }

    private func categoryIdentifier(for title: String) -> String {
        slugify(title) ?? "other"
    }

    private func normalizedAppTitle(from localizedDisplayName: String?, bundleIdentifier: String?) -> String {
        let trimmed = localizedDisplayName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty {
            return trimmed
        }

        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return "Unknown App"
    }

    private func applicationIdentifier(bundleIdentifier: String?, title: String) -> String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return bundleIdentifier
        }

        return slugify(title) ?? UUID().uuidString
    }

    private func slugify(_ value: String) -> String? {
        let scalars = value.lowercased().unicodeScalars.map { scalar -> Character in
            switch scalar {
            case "a"..."z", "0"..."9":
                return Character(scalar)
            default:
                return "-"
            }
        }

        let collapsed = String(scalars)
            .replacingOccurrences(of: "-+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))

        return collapsed.isEmpty ? nil : collapsed
    }

    private func categoryStyle(for title: String) -> CategoryStyle {
        let normalized = title.lowercased()

        if normalized.contains("social") {
            return CategoryStyle(icon: "bubble.left.and.bubble.right.fill", reductionFactor: 0.25, minimumFloor: 15)
        }

        if normalized.contains("game") {
            return CategoryStyle(icon: "gamecontroller.fill", reductionFactor: 0.1, minimumFloor: 10)
        }

        if normalized.contains("entertain") || normalized.contains("video") || normalized.contains("stream") || normalized.contains("tv") {
            return CategoryStyle(icon: "tv.fill", reductionFactor: 0.3, minimumFloor: 15)
        }

        if normalized.contains("shop") || normalized.contains("food") {
            return CategoryStyle(icon: "bag.fill", reductionFactor: 0.35, minimumFloor: 10)
        }

        if normalized.contains("product") || normalized.contains("finance") || normalized.contains("business") {
            return CategoryStyle(icon: "briefcase.fill", reductionFactor: 0.8, minimumFloor: 10)
        }

        if normalized.contains("educat") || normalized.contains("learn") {
            return CategoryStyle(icon: "graduationcap.fill", reductionFactor: 0.9, minimumFloor: 10)
        }

        if normalized.contains("health") || normalized.contains("fitness") {
            return CategoryStyle(icon: "heart.fill", reductionFactor: 0.85, minimumFloor: 10)
        }

        if normalized.contains("read") || normalized.contains("news") || normalized.contains("book") || normalized.contains("information") {
            return CategoryStyle(icon: "book.fill", reductionFactor: 0.7, minimumFloor: 10)
        }

        if normalized.contains("creative") || normalized.contains("photo") || normalized.contains("design") || normalized.contains("art") {
            return CategoryStyle(icon: "paintpalette.fill", reductionFactor: 0.75, minimumFloor: 10)
        }

        if normalized.contains("travel") || normalized.contains("navigation") {
            return CategoryStyle(icon: "airplane", reductionFactor: 0.6, minimumFloor: 10)
        }

        return CategoryStyle(icon: "square.grid.2x2.fill", reductionFactor: 0.6, minimumFloor: 10)
    }

    private func recommendedMinutes(
        currentDailyMinutes: Int,
        reductionFactor: Double,
        minimumFloor: Int
    ) -> Int {
        guard currentDailyMinutes > 0 else {
            return 0
        }

        let rawTarget = Int((Double(currentDailyMinutes) * reductionFactor).rounded())
        return min(
            currentDailyMinutes,
            roundedBudget(minutes: rawTarget, floor: min(minimumFloor, currentDailyMinutes))
        )
    }

    private func roundedBudget(minutes: Int, floor: Int) -> Int {
        guard minutes > 0 else {
            return 0
        }

        let step = minutes < 30 ? 5 : 10
        let rounded = Int((Double(minutes) / Double(step)).rounded()) * step
        return max(rounded, floor)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.allowedUnits = duration >= 3600 ? [.hour, .minute] : [.minute]
        formatter.unitsStyle = .abbreviated
        formatter.zeroFormattingBehavior = .dropAll
        return formatter.string(from: duration) ?? "0m"
    }

    private func formatDuration(minutes: Int) -> String {
        formatDuration(TimeInterval(minutes * 60))
    }
}

private struct CategoryAccumulator {
    let id: String
    let title: String
    let icon: String
    let reductionFactor: Double
    let minimumFloor: Int
    var weeklyTotal: TimeInterval
    var applications: [String: AppAccumulator]
}

private struct AppAccumulator {
    let id: String
    let title: String
    var weeklyTotal: TimeInterval
}

private struct CategoryStyle {
    let icon: String
    let reductionFactor: Double
    let minimumFloor: Int
}

private enum SharedOnboardingUsageSummaryCache {
    private static let groupIdentifier = "group.pear.BlockOS"
    private static let fileName = "onboarding-usage-summary.json"
    private static let defaultsKey = "onboarding-usage-summary"

    static func save(_ summary: OnboardingUsageSummary) {
        guard let data = try? JSONEncoder().encode(summary) else {
            return
        }

        if let sharedDefaults = UserDefaults(suiteName: groupIdentifier) {
            sharedDefaults.set(data, forKey: defaultsKey)
        }

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) {
            let fileURL = containerURL.appendingPathComponent(fileName, conformingTo: .json)

            do {
                try FileManager.default.createDirectory(at: containerURL, withIntermediateDirectories: true)
                try data.write(to: fileURL, options: .atomic)
            } catch {
                return
            }
        }
    }
}
