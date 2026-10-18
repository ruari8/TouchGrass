import DeviceActivity
import ExtensionKit
import FamilyControls
import ManagedSettings
import SwiftUI
import TouchGrassCore
import TouchGrassScreenTime

/// The only place iOS reveals usage minutes. The app embeds these views; their numbers never leave this extension.
@main
struct TouchGrassUsageReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        BudgetUsageReport { usage in
            BudgetUsageView(usage: usage)
        }
    }
}

extension DeviceActivityReport.Context {
    static let budgets = Self("budgets")
}

struct BudgetUsage: Identifiable {
    var id: UUID
    var name: String
    var usedMinutes: Int
    var limitMinutes: Int
}

/// Today's minutes for each enabled Budget, counted over its Block List's apps, categories and sites.
struct BudgetUsageReport: DeviceActivityReportScene {
    let context = DeviceActivityReport.Context.budgets
    let content: ([BudgetUsage]) -> BudgetUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> [BudgetUsage] {
        let state = (try? AppStateStore().load()) ?? AppState()
        let budgets = state.budgets.filter(\.isEnabled)
        let selections = budgets.map { state.blockList(id: $0.blockListID)?.activitySelection ?? FamilyActivitySelection() }
        var seconds = Array(repeating: 0.0, count: budgets.count)

        for await activity in data {
            for await segment in activity.activitySegments {
                for await category in segment.categories {
                    var apps: [(ApplicationToken?, TimeInterval)] = []
                    for await app in category.applications {
                        apps.append((app.application.token, app.totalActivityDuration))
                    }
                    var sites: [(WebDomainToken?, TimeInterval)] = []
                    for await site in category.webDomains {
                        sites.append((site.webDomain.token, site.totalActivityDuration))
                    }
                    for (index, selection) in selections.enumerated() {
                        if let token = category.category.token, selection.categoryTokens.contains(token) {
                            // The whole category counts; don't add its apps again.
                            seconds[index] += category.totalActivityDuration
                            continue
                        }
                        var appSeconds = 0.0
                        for (token, duration) in apps where token.map(selection.applicationTokens.contains) == true {
                            appSeconds += duration
                        }
                        var siteSeconds = 0.0
                        for (token, duration) in sites where token.map(selection.webDomainTokens.contains) == true {
                            siteSeconds += duration
                        }
                        // If the browser itself is on the list too, time on a listed site counts twice.
                        // These bars are display only; Budgets Lock on iOS's own count.
                        seconds[index] += appSeconds + siteSeconds
                    }
                }
            }
        }

        return zip(budgets, seconds).map { budget, seconds in
            BudgetUsage(id: budget.id, name: budget.name, usedMinutes: Int(seconds / 60), limitMinutes: budget.minutes)
        }
    }
}

struct BudgetUsageView: View {
    let usage: [BudgetUsage]
    private let grass = Color(red: 0.45, green: 0.85, blue: 0.40)
    private let locked = Color(red: 0.95, green: 0.45, blue: 0.35)

    var body: some View {
        VStack(spacing: 14) {
            ForEach(usage) { budget in
                let fraction = min(1, Double(budget.usedMinutes) / Double(max(budget.limitMinutes, 1)))
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(budget.name).font(.subheadline.weight(.semibold))
                        Spacer()
                        Text("\(format(budget.usedMinutes)) of \(format(budget.limitMinutes))")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    GeometryReader { proxy in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.secondary.opacity(0.25))
                            Capsule().fill(fraction >= 1 ? locked : grass)
                                .frame(width: proxy.size.width * fraction)
                        }
                    }
                    .frame(height: 8)
                }
            }
        }
        .padding(.horizontal, 2)
    }

    private func format(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60)h \(minutes % 60)m" : "\(minutes)m"
    }
}
