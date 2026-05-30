import Combine
import DeviceActivity
import FamilyControls
import SwiftUI
import UniformTypeIdentifiers
import BlockOSDomain
import BlockOSEnforcement

struct OnboardingFlowView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var step: Step = .permission
    @State private var isActivityPickerPresented = false
    @State private var schedulePreset: BlockSchedulePreset = .allDay
    @State private var customStartHour: Int = 9
    @State private var customEndHour: Int = 18
    @State private var usageSummary: SharedOnboardingUsageSummary?
    @State private var budgetPlan: [CategoryBudgetDraft] = []
    @State private var hasCustomizedBudgetPlan = false
    @State private var skippedIntake = false
    @State private var usageSummaryLoadIssue: String?
    @State private var usageSummaryTimedOut = false
    private let usageSummaryRefreshTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private enum Step: Int, CaseIterable {
        case permission
        case intake
        case configuration
    }

    private enum BlockSchedulePreset: String, CaseIterable {
        case allDay    = "All day"
        case work      = "Work hours"
        case evenings  = "Evenings"
        case mornings  = "Mornings"
        case custom    = "Custom"

        var detail: String {
            switch self {
            case .allDay:   return "Count all day"
            case .work:     return "9am – 6pm"
            case .evenings: return "6pm – 11pm"
            case .mornings: return "6am – 12pm"
            case .custom:   return "Set your own hours"
            }
        }

        var schedule: BlockSchedule? {
            switch self {
            case .allDay:   return nil
            case .work:     return .workHours
            case .evenings: return .evenings
            case .mornings: return .mornings
            case .custom:   return nil
            }
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(UIColor.systemBackground),
                    Color(UIColor.secondarySystemGroupedBackground)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                header

                TabView(selection: $step) {
                    permissionStep.tag(Step.permission)
                    intakeStep.tag(Step.intake)
                    configurationStep.tag(Step.configuration)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
        }
        .familyActivityPicker(
            headerText: blockPickerHeaderText,
            footerText: blockPickerFooterText,
            isPresented: $isActivityPickerPresented,
            selection: $container.activitySelection
        )
        .onChange(of: container.activitySelection) { previousSelection, selection in
            Task { await container.persistSelection(selection, previousSelection: previousSelection) }
        }
        .onAppear {
            if container.authorizationStatus == .approved {
                step = .intake
            }

            loadCachedUsageSummary()

            if usageSummary == nil {
                Task { await refreshUsageSummaryAfterReportRenders() }
            }
        }
        .onChange(of: container.authorizationStatus) { _, status in
            if status == .approved && step == .permission {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    step = .intake
                }

                Task { await refreshUsageSummaryAfterReportRenders() }
            }
        }
        .task(id: step) {
            guard step == .intake || step == .configuration else {
                return
            }

            await refreshUsageSummaryAfterReportRenders()
        }
        .onReceive(usageSummaryRefreshTimer) { _ in
            guard step == .intake || step == .configuration else {
                return
            }

            loadCachedUsageSummary()
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Set up BlockOS")
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                    Text(stepSubtitle)
                        .font(.system(size: 15, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer()

                if step == .intake {
                    Button("Skip") {
                        skippedIntake = true

                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step = .configuration
                        }
                    }
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.secondary)
                }
            }

            HStack(spacing: 10) {
                ForEach(Step.allCases, id: \.self) { currentStep in
                    Capsule()
                        .fill(step.rawValue >= currentStep.rawValue ? Color.primary : Color.primary.opacity(0.12))
                        .frame(height: currentStep == step ? 10 : 6)
                        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: step)
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Step 1: Permission

    private var permissionStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                spotlightCard(
                    eyebrow: "Step 1",
                    title: "Enable Screen Time access",
                    body: "BlockOS needs Family Controls permission before it can read your usage patterns, enforce daily limits, and shield apps after your limit is reached."
                ) {
                    VStack(spacing: 12) {
                        statusPill(
                            icon: container.authorizationStatus == .approved ? "checkmark.shield.fill" : "shield.fill",
                            text: container.authorizationStatus.displayName
                        )

                        OnboardingPrimaryButton(
                            title: container.authorizationStatus == .approved ? "Access Enabled" : "Allow Screen Time Access",
                            subtitle: "Required before BlockOS can do anything useful.",
                            isDisabled: container.isLoading || container.authorizationStatus == .approved
                        ) {
                            Task { await container.requestAuthorization() }
                        }

                        OnboardingSecondaryButton(title: "Continue") {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                step = .intake
                            }
                        }
                        .disabled(container.authorizationStatus != .approved)
                        .opacity(container.authorizationStatus == .approved ? 1 : 0.35)
                    }
                }

                bulletCard(
                    title: "What this unlocks",
                    bullets: [
                        "See your real daily average instead of guessing.",
                        "Break usage down by Screen Time category before you pick blockers.",
                        "Start from a strict category budget, then soften the parts you actually need."
                    ]
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Step 2: Intake

    private var intakeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                spotlightCard(
                    eyebrow: "Your last 7 days",
                    title: "Here is your real average",
                    body: "See the total first, then expand each category to see which apps are actually driving it."
                ) {
                    usageInsightsSection
                }

                spotlightCard(
                    eyebrow: "Starter plan",
                    title: "Set a category budget",
                    body: "Start from the recommendation, or use the 1-hour social starter if Screen Time data is not ready yet."
                ) {
                    budgetPlannerSection
                }

                VStack(spacing: 12) {
                    OnboardingPrimaryButton(
                        title: "Continue to Blocking Setup",
                        subtitle: skippedIntake
                            ? "Pick what to block without saving a screen-time target."
                            : "Carry this target into app and category blocking.",
                        isDisabled: !skippedIntake && budgetPlan.isEmpty
                    ) {
                        skippedIntake = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step = .configuration
                        }
                    }

                    OnboardingSecondaryButton(title: "Skip — I'll just pick apps to block") {
                        skippedIntake = true
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step = .configuration
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Step 3: Configuration

    private var configurationStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                if !skippedIntake {
                    spotlightCard(
                        eyebrow: "Target",
                        title: "What you are enforcing",
                        body: "This is the budget the blocker should protect. The category names match Apple’s picker below."
                    ) {
                        configuredBudgetSummary
                    }
                }

                spotlightCard(
                    eyebrow: "Step 3",
                    title: "Choose what gets blocked",
                    body: "Pick the apps, categories, and websites that should lock after your daily limit."
                ) {
                    VStack(spacing: 12) {
                        if !skippedIntake {
                            HStack {
                                Label(totalBudgetLabel + " daily target", systemImage: "timer")
                                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                        }

                        OnboardingPrimaryButton(
                            title: "Select Apps to Block",
                            subtitle: container.selectionSummary
                        ) {
                            isActivityPickerPresented = true
                        }

                        if !container.makePreviewTargets().isEmpty {
                            Text(container.selectionSummary)
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        } else if !skippedIntake {
                            Text("Start with the categories that blow through the target fastest, then add any specific apps you still want blocked.")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                spotlightCard(
                    eyebrow: "When to block",
                    title: "Daily limit window",
                    body: "Set when usage counts toward the daily limit. Leave on 'All day' for the normal dumb-phone mode."
                ) {
                    scheduleSection
                }

                VStack(spacing: 12) {
                    OnboardingPrimaryButton(
                        title: "Finish Setup",
                        subtitle: "Save daily limits and turn on automatic blocking.",
                        isDisabled: container.makePreviewTargets().isEmpty
                    ) {
                        Task {
                            await container.completeOnboarding(makeProfile())
                        }
                    }

                    OnboardingSecondaryButton(title: "Back") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step = .intake
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    // MARK: - Budget planner

    private var usageInsightsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            UsageInsightsReportLoader()

            if let usageSummary, usageSummary.hasData {
                HStack(spacing: 10) {
                    statusPill(icon: "chart.bar.fill", text: "\(usageSummary.averageDailyText) / day now")
                    statusPill(icon: "scope", text: "\(usageSummary.recommendedDailyText) suggested")
                }
            } else if let usageSummary, !usageSummary.hasData {
                UsageInsightsInlineStatus(
                    title: "No recent Screen Time data",
                    message: "The report came back, but iOS did not provide usable category history for the last 7 days yet."
                )
            } else if let usageSummaryLoadIssue {
                UsageInsightsInlineStatus(
                    title: "Screen Time report unavailable",
                    message: usageSummaryLoadIssue
                )
            } else if usageSummaryTimedOut {
                UsageInsightsInlineStatus(
                    title: "Budget controls are still loading",
                    message: "The report above is ready, but the budget controls below have not finished syncing from Screen Time yet."
                )
            } else {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Loading budget controls from this report.")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }

            Button("Refresh report") {
                reloadUsageSummary()
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
        }
    }

    private var budgetPlannerSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let usageSummary, usageSummary.hasData, !budgetPlan.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        budgetHero(
                            title: "Current",
                            value: usageSummary.averageDailyText,
                            caption: "what the last week actually looks like"
                        )

                        budgetHero(
                            title: "Target",
                            value: totalBudgetLabel,
                            caption: "fully editable below"
                        )
                    }

                    HStack(spacing: 10) {
                        statusPill(icon: "scope", text: "Recommended \(usageSummary.recommendedDailyText) / day")

                        Button("Use recommendation") {
                            applyRecommendedPlan(usageSummary.planRows)
                        }
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(.primary)
                    }

                    Text("Each row shows your current daily average next to the budget you want BlockOS to protect.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                VStack(spacing: 10) {
                    ForEach(Array(budgetPlan.enumerated()), id: \.element.id) { index, row in
                        budgetRow(index: index, row: row)
                    }
                }

                Text("The next screen uses the same category names from Apple’s picker, so the blocker setup maps cleanly to this plan.")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            } else if let usageSummary, !usageSummary.hasData {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Waiting on real category budgets")
                        .font(.system(size: 16, weight: .semibold, design: .rounded))
                    Text("The Screen Time report came back without usable history, so BlockOS cannot recommend category budgets yet. You can refresh, or skip this step and go straight to blocker setup.")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)

                    Button("Refresh categories") {
                        reloadUsageSummary()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                    starterPlanButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    if let usageSummaryLoadIssue {
                        Text("Screen Time planner unavailable")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text(usageSummaryLoadIssue)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else if usageSummaryTimedOut {
                        Text("Budget controls are still loading")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Text("The report above is already visible. The editable budget rows below are still syncing from Screen Time. Refresh once more, or skip this step and continue to blocker setup.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    } else {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.regular)
                            Text("Loading your Screen Time categories")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                        }

                        Text("The planner only appears once the report above finishes loading the real category breakdown.")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                    }

                    Button("Refresh categories") {
                        reloadUsageSummary()
                    }
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundColor(.primary)

                    starterPlanButton
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(18)
                .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
            }
        }
    }

    private var starterPlanButton: some View {
        Button {
            applyStarterPlan()
        } label: {
            HStack {
                Label("Use 1h social starter", systemImage: "bolt.fill")
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
            }
            .font(.system(size: 14, weight: .bold, design: .rounded))
            .foregroundColor(.primary)
            .padding(14)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
    }

    private func budgetHero(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }

    private func budgetRow(index: Int, row: CategoryBudgetDraft) -> some View {
        let currentLabel = row.currentAverageText == "Not loaded"
            ? "Current not loaded"
            : "Current \(row.currentAverageText) / day"

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: row.icon)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 36, height: 36)
                    .background(row.tint.opacity(0.16), in: Circle())
                    .foregroundColor(row.tint)

                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                        .layoutPriority(1)

                    Text(currentLabel)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }

                Spacer(minLength: 12)

                Text(minutesLabel(for: row.targetMinutes))
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.primary.opacity(0.06), in: Capsule())
            }

            HStack {
                Button {
                    updateBudget(at: index, delta: -row.stepSize)
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "minus")
                        Text("Less")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(minWidth: 88, minHeight: 44)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Decrease \(row.title) budget")

                Spacer()

                Text("Target")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                Spacer()

                Button {
                    updateBudget(at: index, delta: row.stepSize)
                } label: {
                    HStack(spacing: 6) {
                        Text("More")
                        Image(systemName: "plus")
                    }
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .frame(minWidth: 88, minHeight: 44)
                    .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Increase \(row.title) budget")
            }
        }
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }

    private var configuredBudgetSummary: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(totalBudgetLabel)
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("/ day")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
                ForEach(budgetPlan.filter { $0.targetMinutes > 0 }, id: \.id) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.icon)
                            .font(.system(size: 11, weight: .bold))
                            .frame(width: 28, height: 28)
                            .background(row.tint.opacity(0.15), in: Circle())
                            .foregroundColor(row.tint)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.title)
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)
                            Text(minutesLabel(for: row.targetMinutes))
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 16))
                }
            }
        }
    }

    // MARK: - Schedule section

    private var scheduleSection: some View {
        VStack(spacing: 12) {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 10) {
                ForEach(BlockSchedulePreset.allCases, id: \.self) { preset in
                    Button {
                        schedulePreset = preset
                    } label: {
                        VStack(spacing: 3) {
                            Text(preset.rawValue)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                            Text(preset.detail)
                                .font(.system(size: 11, weight: .medium, design: .rounded))
                                .foregroundColor(
                                    schedulePreset == preset
                                        ? Color(UIColor.systemBackground).opacity(0.7)
                                        : .secondary
                                )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            schedulePreset == preset
                                ? Color.primary
                                : Color.primary.opacity(0.07),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                        .foregroundColor(
                            schedulePreset == preset
                                ? Color(UIColor.systemBackground)
                                : .primary
                        )
                    }
                    .buttonStyle(.plain)
                }
            }

            if schedulePreset == .custom {
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("From")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Picker("Start", selection: $customStartHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Until")
                            .font(.system(size: 12, weight: .bold, design: .rounded))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                        Picker("End", selection: $customEndHour) {
                            ForEach(0..<24, id: \.self) { h in
                                Text(hourLabel(h)).tag(h)
                            }
                        }
                        .pickerStyle(.wheel)
                        .frame(height: 150)
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    // MARK: - Helpers

    private var totalBudgetMinutes: Int {
        budgetPlan.reduce(0) { $0 + $1.targetMinutes }
    }

    private var totalBudgetLabel: String {
        budgetPlan.isEmpty ? "—" : minutesLabel(for: totalBudgetMinutes)
    }

    private var blockPickerHeaderText: String? {
        guard !skippedIntake else {
            return "Choose the apps and categories BlockOS should put behind friction."
        }

        guard !budgetPlan.isEmpty else {
            return nil
        }

        if let usageSummary, usageSummary.hasData {
            return "Current average \(usageSummary.averageDailyText) per day. Target \(totalBudgetLabel) per day."
        }

        return "Target \(totalBudgetLabel) per day."
    }

    private var blockPickerFooterText: String? {
        guard !skippedIntake else {
            return "Pick categories first if your issue is broad, then add specific apps if needed."
        }

        guard !budgetPlan.isEmpty else {
            return nil
        }

        let leadingRows = budgetPlan
            .filter { $0.targetMinutes > 0 }
            .prefix(3)
            .map { "\($0.title) \(minutesLabel(for: $0.targetMinutes))" }
            .joined(separator: " • ")

        guard !leadingRows.isEmpty else {
            return nil
        }

        return "Budget focus: \(leadingRows)"
    }

    private var stepSubtitle: String {
        switch step {
        case .permission:
            return "Give BlockOS permission to do the job."
        case .intake:
            return "See your habits, then set category budgets."
        case .configuration:
            return "Pick blockers and a schedule."
        }
    }

    private func loadCachedUsageSummary() {
        switch SharedOnboardingUsageSummaryCache.loadStatus() {
        case let .summary(summary):
            usageSummaryLoadIssue = nil
            usageSummaryTimedOut = false

            guard usageSummary != summary else {
                return
            }

            usageSummary = summary

            if summary.hasData && !hasCustomizedBudgetPlan {
                budgetPlan = CategoryBudgetDraft.makePlan(from: summary.planRows)
            } else if !summary.hasData && !hasCustomizedBudgetPlan {
                budgetPlan = []
            }
        case .appGroupUnavailable:
            usageSummaryLoadIssue = "The shared App Group container is unavailable for this build, so the usage report cannot hand category data back to onboarding. Enable App Groups for both BlockOS and BlockOSUsageReport, then rerun."
        case .missingData:
            break
        }
    }

    private func refreshUsageSummaryAfterReportRenders() async {
        loadCachedUsageSummary()

        if usageSummary != nil || usageSummaryLoadIssue != nil {
            return
        }

        for delay in [400_000_000, 1_000_000_000, 2_000_000_000] {
            try? await Task.sleep(nanoseconds: UInt64(delay))
            loadCachedUsageSummary()

            if usageSummary != nil || usageSummaryLoadIssue != nil {
                return
            }
        }

        usageSummaryTimedOut = true
    }

    private func reloadUsageSummary() {
        usageSummaryTimedOut = false
        loadCachedUsageSummary()
        Task { await refreshUsageSummaryAfterReportRenders() }
    }

    private func applyRecommendedPlan(_ rows: [SharedOnboardingUsageSummary.PlanRow]) {
        guard !rows.isEmpty else {
            return
        }

        skippedIntake = false
        hasCustomizedBudgetPlan = true
        budgetPlan = CategoryBudgetDraft.makePlan(from: rows)
    }

    private func applyStarterPlan() {
        skippedIntake = false
        hasCustomizedBudgetPlan = true
        usageSummaryTimedOut = false
        budgetPlan = CategoryBudgetDraft.starterPlan()
    }

    private func updateBudget(at index: Int, delta: Int) {
        guard budgetPlan.indices.contains(index) else {
            return
        }

        hasCustomizedBudgetPlan = true
        skippedIntake = false
        budgetPlan[index].targetMinutes = max(0, budgetPlan[index].targetMinutes + delta)
    }

    private func makeProfile() -> OnboardingProfile {
        let goalPlan: ScreenTimeGoalPlan? = (skippedIntake || budgetPlan.isEmpty) ? nil : {
            let socialBudget = budgetPlan.first(where: { $0.id.lowercased().contains("social") })?.targetMinutes ?? 0
            let categoryBudgets = budgetPlan
                .filter { $0.targetMinutes > 0 }
                .map { row in
                    ScreenTimeCategoryBudget(
                        categoryKey: row.id,
                        displayName: row.title,
                        minutes: row.targetMinutes
                    )
                }

            let reductionFocus = usageSummary?.planRows
                .max(by: { $0.currentAverageMinutes < $1.currentAverageMinutes })?
                .title ?? categoryBudgets.first?.displayName ?? "Social media"

            return ScreenTimeGoalPlan(
                reductionFocus: reductionFocus,
                idealDailyMinutes: totalBudgetMinutes,
                socialMediaMinutes: socialBudget,
                everythingElseMinutes: max(totalBudgetMinutes - socialBudget, 0),
                categoryBudgets: categoryBudgets
            )
        }()

        let schedule: BlockSchedule? = {
            switch schedulePreset {
            case .allDay:
                return nil
            case .custom:
                return BlockSchedule(startHour: customStartHour, endHour: customEndHour)
            default:
                return schedulePreset.schedule
            }
        }()

        return OnboardingProfile(
            skippedIntake: skippedIntake,
            goalPlan: goalPlan,
            schedule: schedule
        )
    }

    private func minutesLabel(for minutes: Int) -> String {
        if minutes == 0 { return "0m" }
        if minutes % 60 == 0 { return "\(minutes / 60)h" }
        if minutes > 60 { return "\(minutes / 60)h \(minutes % 60)m" }
        return "\(minutes)m"
    }

    private func hourLabel(_ h: Int) -> String {
        let period = h < 12 ? "am" : "pm"
        let display = h == 0 ? 12 : (h > 12 ? h - 12 : h)
        return "\(display)\(period)"
    }

    // MARK: - Card builders

    private func spotlightCard<Content: View>(
        eyebrow: String,
        title: String,
        body: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(eyebrow)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                Text(body)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(22)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: Color.black.opacity(0.05), radius: 18, y: 10)
    }

    private func bulletCard(title: String, bullets: [String]) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            ForEach(bullets, id: \.self) { bullet in
                HStack(alignment: .top, spacing: 10) {
                    Circle()
                        .fill(Color.primary)
                        .frame(width: 7, height: 7)
                        .padding(.top, 6)
                    Text(bullet)
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(22)
        .background(Color(UIColor.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 28))
        .shadow(color: Color.black.opacity(0.04), radius: 14, y: 8)
    }

    private func statusPill(icon: String, text: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(text)
        }
        .font(.system(size: 13, weight: .bold, design: .rounded))
        .foregroundColor(.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06), in: Capsule())
    }
}

// MARK: - Sub-views

private struct UsageInsightsReportLoader: View {
    private let interval = DateInterval(
        start: Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? Calendar.current.startOfDay(for: .now),
        end: .now
    )

    var body: some View {
        DeviceActivityReport(
            .blockOSOnboarding,
            filter: DeviceActivityFilter(segment: .daily(during: interval))
        )
        .frame(maxWidth: .infinity, minHeight: 560, alignment: .topLeading)
    }
}

private struct UsageInsightsInlineStatus: View {
    let title: String
    let message: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))

            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}

private extension DeviceActivityReport.Context {
    static let blockOSOnboarding = Self("BlockOS Onboarding")
}

private struct UsageInsightsStatusCard<Accessory: View>: View {
    let title: String
    let message: String
    @ViewBuilder let accessory: () -> Accessory

    init(
        title: String,
        body: String,
        @ViewBuilder accessory: @escaping () -> Accessory
    ) {
        self.title = title
        self.message = body
        self.accessory = accessory
    }

    var bodyView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .bold, design: .rounded))

            Text(message)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            accessory()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 20))
    }

    var body: some View {
        bodyView
    }
}

private struct UsageInsightsSummarySnapshot: View {
    let summary: SharedOnboardingUsageSummary

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                snapshotMetric(
                    title: "Current",
                    value: summary.averageDailyText,
                    caption: "\(summary.weeklyTotalText) over the last \(summary.daysTracked) days"
                )

                snapshotMetric(
                    title: "Suggested",
                    value: summary.recommendedDailyText,
                    caption: "Starting daily target"
                )
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Category breakdown")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .textCase(.uppercase)

                ForEach(summary.categories, id: \.id) { category in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: category.icon)
                            .font(.system(size: 12, weight: .bold))
                            .frame(width: 32, height: 32)
                            .background(categoryTint(for: category.id).opacity(0.15), in: Circle())
                            .foregroundColor(categoryTint(for: category.id))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.title)
                                .font(.system(size: 15, weight: .semibold, design: .rounded))
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            Text("\(category.dailyAverageText) / day now")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        Spacer(minLength: 12)

                        VStack(alignment: .trailing, spacing: 4) {
                            Text(category.recommendedText)
                                .font(.system(size: 15, weight: .bold, design: .rounded))
                            Text("target")
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(14)
                    .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func snapshotMetric(title: String, value: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)

            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))

            Text(caption)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 22))
    }

    private func categoryTint(for id: String) -> Color {
        let normalized = id.lowercased()

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
            return .primary
        }
    }
}

private struct OnboardingPrimaryButton: View {
    let title: String
    let subtitle: String
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundColor(Color(UIColor.systemBackground).opacity(0.8))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(18)
            .background(isDisabled ? Color.primary.opacity(0.25) : Color.primary, in: RoundedRectangle(cornerRadius: 20))
            .foregroundColor(Color(UIColor.systemBackground))
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

private struct OnboardingSecondaryButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
                .foregroundColor(.primary)
        }
        .buttonStyle(.plain)
    }
}

private struct CategoryBudgetDraft {
    let id: String
    let title: String
    let icon: String
    let tint: Color
    let currentAverageMinutes: Int
    let currentAverageText: String
    var targetMinutes: Int

    var stepSize: Int {
        targetMinutes < 30 ? 5 : 10
    }

    static func makePlan(from rows: [SharedOnboardingUsageSummary.PlanRow]) -> [CategoryBudgetDraft] {
        return rows.map { row in
            CategoryBudgetDraft(
                id: row.id,
                title: row.title,
                icon: row.icon,
                tint: tint(for: row.id),
                currentAverageMinutes: row.currentAverageMinutes,
                currentAverageText: row.currentAverageText,
                targetMinutes: row.targetMinutes
            )
        }
    }

    static func starterPlan() -> [CategoryBudgetDraft] {
        [
            CategoryBudgetDraft(
                id: "social",
                title: "Social",
                icon: "bubble.left.and.bubble.right.fill",
                tint: tint(for: "social"),
                currentAverageMinutes: 0,
                currentAverageText: "Not loaded",
                targetMinutes: 60
            ),
            CategoryBudgetDraft(
                id: "entertainment",
                title: "Entertainment",
                icon: "tv.fill",
                tint: tint(for: "entertainment"),
                currentAverageMinutes: 0,
                currentAverageText: "Not loaded",
                targetMinutes: 30
            ),
            CategoryBudgetDraft(
                id: "games",
                title: "Games",
                icon: "gamecontroller.fill",
                tint: tint(for: "games"),
                currentAverageMinutes: 0,
                currentAverageText: "Not loaded",
                targetMinutes: 20
            )
        ]
    }

    private static func tint(for id: String) -> Color {
        let normalized = id.lowercased()

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
            return .primary
        }
    }
}

private struct SharedOnboardingUsageSummary: Codable, Equatable {
    struct AppUsage: Codable, Equatable {
        let id: String
        let title: String
        let dailyAverageMinutes: Int
        let dailyAverageText: String
        let weeklyTotalText: String
        let shareOfCategory: Double
    }

    struct CategoryUsage: Codable, Equatable {
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

    struct PlanRow: Codable, Equatable {
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

private enum SharedOnboardingUsageSummaryCache {
    private static let groupIdentifier = "group.pear.BlockOS"
    private static let fileName = "onboarding-usage-summary.json"
    private static let defaultsKey = "onboarding-usage-summary"

    static func loadStatus() -> SharedOnboardingUsageSummaryCacheLoadStatus {
        let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
        let sharedDefaults = UserDefaults(suiteName: groupIdentifier)

        if let containerURL {
            let fileURL = containerURL.appendingPathComponent(fileName, conformingTo: .json)

            if let data = try? Data(contentsOf: fileURL),
               let summary = try? JSONDecoder().decode(SharedOnboardingUsageSummary.self, from: data) {
                return .summary(summary)
            }
        }

        if let data = sharedDefaults?.data(forKey: defaultsKey),
           let summary = try? JSONDecoder().decode(SharedOnboardingUsageSummary.self, from: data) {
            return .summary(summary)
        }

        if containerURL == nil && sharedDefaults == nil {
            return .appGroupUnavailable
        }

        return .missingData
    }
}

private enum SharedOnboardingUsageSummaryCacheLoadStatus {
    case summary(SharedOnboardingUsageSummary)
    case appGroupUnavailable
    case missingData
}

private extension RestrictionAuthorizationStatus {
    var displayName: String {
        switch self {
        case .notDetermined: return "Waiting for permission"
        case .denied:        return "Access denied"
        case .approved:      return "Access enabled"
        }
    }
}
