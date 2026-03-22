import SwiftUI

struct OnboardingUsageSummaryView: View {
    let summary: OnboardingUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Pattern")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)
                    Text(summary.hasData ? summary.averageDailyText : "No recent data")
                        .font(.system(size: 32, weight: .bold, design: .rounded))
                    Text(summary.hasData ? "Average tracked day" : summary.weeklyTotalText)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if summary.hasData {
                    VStack(alignment: .trailing, spacing: 6) {
                        Text("Last 7 days")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Text(summary.weeklyTotalText)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                    }
                }
            }

            if summary.hasData {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Top time sinks")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundColor(.secondary)
                        .textCase(.uppercase)

                    ForEach(Array(summary.topApps.enumerated()), id: \.offset) { _, app in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(Color.primary.opacity(0.1))
                                .frame(width: 36, height: 36)
                                .overlay(
                                    Image(systemName: "app.fill")
                                        .font(.system(size: 14, weight: .semibold))
                                )

                            VStack(alignment: .leading, spacing: 2) {
                                Text(app.name)
                                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                                Text(app.durationText)
                                    .font(.system(size: 13, weight: .medium, design: .rounded))
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                        .padding(14)
                        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.clear)
    }
}

#Preview {
    OnboardingUsageSummaryView(
        summary: OnboardingUsageSummary(
            averageDailyText: "5h 12m",
            weeklyTotalText: "36h 24m",
            topApps: [
                .init(name: "Instagram", durationText: "9h 10m"),
                .init(name: "Vinted", durationText: "6h 48m"),
                .init(name: "YouTube", durationText: "4h 02m")
            ],
            hasData: true
        )
    )
}
