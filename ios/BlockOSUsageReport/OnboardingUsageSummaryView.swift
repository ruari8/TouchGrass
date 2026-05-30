import SwiftUI

struct OnboardingUsageSummaryView: View {
    let summary: OnboardingUsageSummary
    @State private var expandedCategoryIDs: Set<String> = []

    var body: some View {
        if summary.hasData {
            dataView
        } else {
            emptyView
        }
    }

    private var dataView: some View {
        VStack(alignment: .leading, spacing: 24) {
            heroSection
            categoryBreakdownSection
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Current average")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(summary.averageDailyText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                Text("/ day")
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            Text("\(summary.weeklyTotalText) over the last \(summary.daysTracked) days")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            HStack(spacing: 12) {
                heroMetric(
                    title: "Suggested target",
                    value: summary.recommendedDailyText,
                    caption: "Starting point"
                )

                heroMetric(
                    title: "Categories",
                    value: "\(summary.categories.count)",
                    caption: "Tap to expand apps"
                )
            }
        }
    }

    private var categoryBreakdownSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Category breakdown")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text("Tap any category to see which apps are actually creating that total.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)

            ForEach(summary.categories, id: \.id) { category in
                VStack(alignment: .leading, spacing: 12) {
                    Button {
                        toggleExpanded(category.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: category.icon)
                                    .font(.system(size: 12, weight: .bold))
                                    .frame(width: 34, height: 34)
                                    .background(tint(for: category.id).opacity(0.15), in: Circle())
                                    .foregroundColor(tint(for: category.id))

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.title)
                                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                                        .lineLimit(2)
                                        .fixedSize(horizontal: false, vertical: true)

                                    Text(category.apps.isEmpty ? "No app breakdown available" : "\(category.apps.count) apps")
                                        .font(.system(size: 12, weight: .medium, design: .rounded))
                                        .foregroundColor(.secondary)
                                }

                                Spacer(minLength: 12)

                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(category.dailyAverageText)
                                        .font(.system(size: 16, weight: .bold, design: .rounded))
                                    Image(systemName: expandedCategoryIDs.contains(category.id) ? "chevron.up" : "chevron.down")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundColor(.secondary)
                                }
                            }

                            GeometryReader { geometry in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.primary.opacity(0.08))
                                        .frame(height: 10)

                                    Capsule()
                                        .fill(tint(for: category.id).opacity(0.28))
                                        .frame(
                                            width: max(10, geometry.size.width * min(category.shareOfTotal, 1)),
                                            height: 10
                                        )

                                    Capsule()
                                        .fill(tint(for: category.id))
                                        .frame(
                                            width: max(
                                                6,
                                                geometry.size.width * min(
                                                    summary.averageDailyMinutes == 0
                                                        ? 0
                                                        : Double(category.recommendedMinutes) / Double(summary.averageDailyMinutes),
                                                    1
                                                )
                                            ),
                                            height: 10
                                        )
                                }
                            }
                            .frame(height: 10)

                            HStack {
                                Text("Current \(category.dailyAverageText)")
                                Spacer()
                                Text("Target \(category.recommendedText)")
                            }
                            .font(.system(size: 11, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)

                    if expandedCategoryIDs.contains(category.id) {
                        appBreakdown(for: category)
                    }
                }
                .padding(.vertical, 12)
                .padding(.horizontal, 14)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 18))
            }
        }
    }

    private func appBreakdown(for category: OnboardingUsageSummary.CategoryUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .overlay(Color.primary.opacity(0.08))

            if category.apps.isEmpty {
                Text("App-level usage was not available for this category.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            } else {
                ForEach(category.apps, id: \.id) { app in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text(app.title)
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Spacer(minLength: 12)

                            Text(app.dailyAverageText)
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                        }

                        HStack {
                            Text(app.weeklyTotalText + " total this week")
                            Spacer()
                            Text(shareLabel(for: app.shareOfCategory))
                        }
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)

                        GeometryReader { geometry in
                            Capsule()
                                .fill(tint(for: category.id).opacity(0.22))
                                .frame(
                                    width: max(8, geometry.size.width * min(app.shareOfCategory, 1)),
                                    height: 6
                                )
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.primary.opacity(0.06), in: Capsule())
                        }
                        .frame(height: 6)
                    }
                    .padding(.vertical, 6)
                }
            }
        }
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 32, weight: .light))
                .foregroundColor(.secondary)
            Text("No recent data")
                .font(.system(size: 17, weight: .bold, design: .rounded))
            Text("Open your usual apps for a day or two, then revisit this setup.")
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }

    private func heroMetric(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 22, weight: .bold, design: .rounded))

            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 18))
    }

    private func toggleExpanded(_ id: String) {
        if expandedCategoryIDs.contains(id) {
            expandedCategoryIDs.remove(id)
        } else {
            expandedCategoryIDs.insert(id)
        }
    }

    private func shareLabel(for share: Double) -> String {
        let percent = Int((share * 100).rounded())
        return "\(percent)% of category"
    }

    private func tint(for categoryID: String) -> Color {
        let normalized = categoryID.lowercased()

        switch normalized {
        case let value where value.contains("social"):
            return Color(red: 0.98, green: 0.35, blue: 0.55)
        case let value where value.contains("game"):
            return Color(red: 0.39, green: 0.61, blue: 0.99)
        case let value where value.contains("entertain") || value.contains("video") || value.contains("stream"):
            return Color(red: 0.99, green: 0.67, blue: 0.21)
        case let value where value.contains("creative") || value.contains("photo") || value.contains("design"):
            return Color(red: 0.93, green: 0.54, blue: 0.26)
        case let value where value.contains("educat") || value.contains("learn"):
            return Color(red: 0.35, green: 0.73, blue: 0.41)
        case let value where value.contains("health") || value.contains("fitness"):
            return Color(red: 0.95, green: 0.39, blue: 0.39)
        case let value where value.contains("read") || value.contains("book") || value.contains("information"):
            return Color(red: 0.39, green: 0.77, blue: 0.75)
        case let value where value.contains("product") || value.contains("finance") || value.contains("business"):
            return Color(red: 0.49, green: 0.58, blue: 0.98)
        case let value where value.contains("shop") || value.contains("food"):
            return Color(red: 0.97, green: 0.54, blue: 0.28)
        case let value where value.contains("travel") || value.contains("navigation"):
            return Color(red: 0.38, green: 0.75, blue: 0.56)
        default:
            return Color.primary
        }
    }
}

#Preview {
    OnboardingUsageSummaryView(
        summary: OnboardingUsageSummary(
            averageDailyMinutes: 298,
            averageDailyText: "4h 58m",
            weeklyTotalText: "34h 46m",
            recommendedDailyMinutes: 95,
            recommendedDailyText: "1h 35m",
            categories: [
                .init(
                    id: "social",
                    title: "Social",
                    icon: "bubble.left.and.bubble.right.fill",
                    dailyAverageMinutes: 217,
                    dailyAverageText: "3h 37m",
                    weeklyTotalText: "25h 19m",
                    recommendedMinutes: 50,
                    recommendedText: "50m",
                    shareOfTotal: 0.73,
                    apps: [
                        .init(id: "com.burbn.instagram", title: "Instagram", dailyAverageMinutes: 96, dailyAverageText: "1h 36m", weeklyTotalText: "11h 12m", shareOfCategory: 0.44),
                        .init(id: "com.zhiliaoapp.musically", title: "TikTok", dailyAverageMinutes: 74, dailyAverageText: "1h 14m", weeklyTotalText: "8h 38m", shareOfCategory: 0.34),
                        .init(id: "com.reddit.Reddit", title: "Reddit", dailyAverageMinutes: 47, dailyAverageText: "47m", weeklyTotalText: "5h 29m", shareOfCategory: 0.22),
                    ]
                ),
                .init(
                    id: "entertainment",
                    title: "Entertainment",
                    icon: "tv.fill",
                    dailyAverageMinutes: 41,
                    dailyAverageText: "41m",
                    weeklyTotalText: "4h 47m",
                    recommendedMinutes: 15,
                    recommendedText: "15m",
                    shareOfTotal: 0.14,
                    apps: [
                        .init(id: "com.netflix.Netflix", title: "Netflix", dailyAverageMinutes: 23, dailyAverageText: "23m", weeklyTotalText: "2h 41m", shareOfCategory: 0.56),
                        .init(id: "com.google.ios.youtube", title: "YouTube", dailyAverageMinutes: 18, dailyAverageText: "18m", weeklyTotalText: "2h 6m", shareOfCategory: 0.44),
                    ]
                ),
                .init(
                    id: "other",
                    title: "Other",
                    icon: "square.grid.2x2.fill",
                    dailyAverageMinutes: 16,
                    dailyAverageText: "16m",
                    weeklyTotalText: "1h 52m",
                    recommendedMinutes: 10,
                    recommendedText: "10m",
                    shareOfTotal: 0.05,
                    apps: [
                        .init(id: "com.apple.Maps", title: "Maps", dailyAverageMinutes: 9, dailyAverageText: "9m", weeklyTotalText: "1h 3m", shareOfCategory: 0.56),
                        .init(id: "com.apple.weather", title: "Weather", dailyAverageMinutes: 7, dailyAverageText: "7m", weeklyTotalText: "49m", shareOfCategory: 0.44),
                    ]
                ),
            ],
            planRows: [
                .init(id: "social", title: "Social", icon: "bubble.left.and.bubble.right.fill", currentAverageMinutes: 217, currentAverageText: "3h 37m", targetMinutes: 50, targetText: "50m"),
                .init(id: "entertainment", title: "Entertainment", icon: "tv.fill", currentAverageMinutes: 41, currentAverageText: "41m", targetMinutes: 15, targetText: "15m"),
                .init(id: "other", title: "Other", icon: "square.grid.2x2.fill", currentAverageMinutes: 16, currentAverageText: "16m", targetMinutes: 10, targetText: "10m"),
            ],
            hasData: true,
            daysTracked: 7
        )
    )
    .padding()
    .background(Color(UIColor.secondarySystemGroupedBackground))
}
