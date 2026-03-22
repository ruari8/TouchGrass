import DeviceActivity
import FamilyControls
import SwiftUI
import BlockOSDomain
import BlockOSEnforcement

struct OnboardingFlowView: View {
    @EnvironmentObject private var container: AppContainer
    @State private var step: Step = .permission
    @State private var isActivityPickerPresented = false
    @State private var feeling: OnboardingFeeling = .concerned
    @State private var reductionFocus = "Social scrolling"
    @State private var idealDailyMinutes = 90.0
    @State private var socialMediaMinutes = 45.0
    @State private var didSkipIntake = false
    @State private var aiRecommendation: OnboardingCoachRecommendation?
    @State private var aiRecommendationSignature: String?
    @State private var aiRecommendationError: String?
    @State private var isLoadingAIRecommendation = false
    @State private var hasRequestedInitialAIRecommendation = false

    private let onboardingCoach = OpenRouterOnboardingCoach()

    private enum Step: Int, CaseIterable {
        case permission
        case intake
        case configuration
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
        .familyActivityPicker(isPresented: $isActivityPickerPresented, selection: $container.activitySelection)
        .onChange(of: container.activitySelection) { previousSelection, selection in
            Task { await container.persistSelection(selection, previousSelection: previousSelection) }
        }
        .onAppear {
            if container.authorizationStatus == .approved {
                step = .intake
            }
        }
        .onChange(of: container.authorizationStatus) { _, status in
            if status == .approved && step == .permission {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    step = .intake
                }
            }
        }
        .onChange(of: feeling) { _, _ in markRecommendationStale() }
        .onChange(of: reductionFocus) { _, _ in markRecommendationStale() }
        .onChange(of: idealDailyMinutes) { _, _ in markRecommendationStale() }
        .onChange(of: socialMediaMinutes) { _, _ in markRecommendationStale() }
    }

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
                        didSkipIntake = true
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

    private var permissionStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 24) {
                spotlightCard(
                    eyebrow: "Step 1",
                    title: "Enable Screen Time access",
                    body: "BlockOS needs Family Controls permission before it can read your usage patterns, configure app shields, or enforce the focus setup you choose."
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
                        "See your current daily usage and biggest time sinks.",
                        "Choose what to block without leaving onboarding.",
                        "Set a target that turns your phone into something more intentional."
                    ]
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var intakeStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                spotlightCard(
                    eyebrow: "Step 2",
                    title: "Look at the pattern first",
                    body: "Before you choose blocks, BlockOS should show you what your phone is currently training you to do."
                ) {
                    UsageInsightsReportCard()
                        .frame(minHeight: 250)
                }

                spotlightCard(
                    eyebrow: "Reflection",
                    title: "How does your current screen time feel?",
                    body: "This is optional, but the recommendation gets better if BlockOS knows whether you feel calm, uneasy, or outmatched."
                ) {
                    feelingSelector
                }

                spotlightCard(
                    eyebrow: "Goal",
                    title: "What do you want to reduce first?",
                    body: "Name the behavior you want this phone to stop rewarding."
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        TextField("Social scrolling, shopping, late-night browsing...", text: $reductionFocus)
                            .textInputAutocapitalization(.sentences)
                            .font(.system(size: 16, weight: .medium, design: .rounded))
                            .padding(16)
                            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Ideal daily screen time")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                            Text(minutesLabel(for: Int(idealDailyMinutes)))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Slider(
                                value: $idealDailyMinutes,
                                in: 30...300,
                                step: 15,
                                onEditingChanged: { _ in clampBreakdown() }
                            )
                            .tint(.primary)
                        }
                    }
                }

                spotlightCard(
                    eyebrow: "Breakdown",
                    title: "Split that time with intent",
                    body: "A simple starting split is social media versus everything else. The buckets should add up to your daily target."
                ) {
                    VStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Social media")
                                Spacer()
                                Text(minutesLabel(for: Int(socialMediaMinutes)))
                                    .foregroundColor(.secondary)
                            }
                            Slider(
                                value: $socialMediaMinutes,
                                in: 0...idealDailyMinutes,
                                step: 15,
                                onEditingChanged: { _ in clampBreakdown() }
                            )
                            .tint(.primary)
                        }

                        HStack {
                            breakdownMetric(title: "Social", value: minutesLabel(for: Int(socialMediaMinutes)))
                            breakdownMetric(title: "Everything Else", value: minutesLabel(for: everythingElseMinutes))
                        }
                    }
                }

                spotlightCard(
                    eyebrow: "Recommendation",
                    title: activeRecommendationTitle,
                    body: activeRecommendationSubtitle
                ) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(activeRecommendationBody)
                            .font(.system(size: 15, weight: .medium, design: .rounded))
                            .foregroundColor(.secondary)
                        if !activeRecommendedBlockTargets.isEmpty {
                            Text("Start by blocking: \(activeRecommendedBlockTargets.joined(separator: ", "))")
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                        }

                        if let aiRecommendationError {
                            Text(aiRecommendationError)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        } else if !onboardingCoach.isConfigured {
                            Text("Using the local BlockOS recommendation. Add `BLOCKOS_OPENROUTER_API_KEY` to enable the AI coach.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        } else if isRecommendationStale {
                            Text("Your answers changed. Refresh the AI recommendation to match your latest plan.")
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                        }

                        HStack(spacing: 12) {
                            if isLoadingAIRecommendation {
                                ProgressView()
                                    .controlSize(.small)
                            }

                            if onboardingCoach.isConfigured {
                                Button(isRecommendationStale || aiRecommendation == nil ? "Generate AI Recommendation" : "Refresh AI Recommendation") {
                                    Task { await refreshAIRecommendation() }
                                }
                                .font(.system(size: 14, weight: .semibold, design: .rounded))
                                .foregroundColor(.primary)
                                .disabled(isLoadingAIRecommendation)
                            }
                        }
                    }
                }
                .task {
                    guard
                        step == .intake,
                        onboardingCoach.isConfigured,
                        !hasRequestedInitialAIRecommendation
                    else {
                        return
                    }

                    hasRequestedInitialAIRecommendation = true
                    await refreshAIRecommendation()
                }

                VStack(spacing: 12) {
                    OnboardingPrimaryButton(
                        title: "Continue to Configuration",
                        subtitle: "Choose the apps that should hit the wall first."
                    ) {
                        didSkipIntake = false
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step = .configuration
                        }
                    }

                    OnboardingSecondaryButton(title: "Skip This For Now") {
                        didSkipIntake = true
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

    private var configurationStep: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 20) {
                spotlightCard(
                    eyebrow: "Step 3",
                    title: "Choose what gets blocked",
                    body: "This is where BlockOS turns your plan into friction. Pick the apps, categories, and sites that should stop being available on impulse."
                ) {
                    VStack(spacing: 12) {
                        if !didSkipIntake {
                            HStack(spacing: 12) {
                                breakdownMetric(title: "Daily Goal", value: minutesLabel(for: Int(idealDailyMinutes)))
                                breakdownMetric(title: "Social", value: minutesLabel(for: Int(socialMediaMinutes)))
                                breakdownMetric(title: "Other", value: minutesLabel(for: everythingElseMinutes))
                            }
                        }

                        OnboardingPrimaryButton(
                            title: "Select Apps To Block",
                            subtitle: container.selectionSummary
                        ) {
                            isActivityPickerPresented = true
                        }

                        if !container.makePreviewTargets().isEmpty {
                            Text("Current selection: \(container.selectionSummary)")
                                .font(.system(size: 14, weight: .medium, design: .rounded))
                                .foregroundColor(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                bulletCard(
                    title: "How this setup will work",
                    bullets: [
                        "BlockOS can only add more blocks during an active focus session.",
                        "Emergency Unblock still exists when real life interrupts the plan.",
                        "The branded shield now sends people back to BlockOS instead of the generic Restricted screen."
                    ]
                )

                VStack(spacing: 12) {
                    OnboardingPrimaryButton(
                        title: "Finish Setup",
                        subtitle: "Save this setup and drop into the main app.",
                        isDisabled: container.makePreviewTargets().isEmpty
                    ) {
                        Task {
                            await container.completeOnboarding(makeProfile())
                        }
                    }

                    OnboardingSecondaryButton(title: "Back") {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            step = didSkipIntake ? .intake : .intake
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private var feelingSelector: some View {
        VStack(spacing: 10) {
            ForEach(OnboardingFeeling.allCases, id: \.self) { currentFeeling in
                Button {
                    feeling = currentFeeling
                } label: {
                    HStack {
                        Text(currentFeeling.displayName)
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        Spacer()
                        Image(systemName: feeling == currentFeeling ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 18, weight: .bold))
                    }
                    .foregroundColor(.primary)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 18)
                            .fill(feeling == currentFeeling ? Color.primary.opacity(0.08) : Color.primary.opacity(0.03))
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var everythingElseMinutes: Int {
        max(Int(idealDailyMinutes) - Int(socialMediaMinutes), 0)
    }

    private var fallbackRecommendationTitle: String {
        switch feeling {
        case .okay:
            return "You do not need to go nuclear. Make the phone a little harder to abuse, not impossible to use."
        case .concerned:
            return "Aim for a visible cut, not a fantasy number. The first win is proving you can stay below your old baseline."
        case .frustrated:
            return "Use a tighter social bucket and make your worst habit physically inconvenient to reach."
        case .overwhelmed:
            return "Start strict. Reduce the cheap dopamine first, then earn flexibility back once the compulsion fades."
        }
    }

    private var fallbackRecommendationBody: String {
        if didSkipIntake {
            return "You skipped the reflection step, so BlockOS will keep the setup lean: choose the apps that derail you most often and start with a simple block list."
        }

        let socialShare = idealDailyMinutes == 0 ? 0 : Int((socialMediaMinutes / idealDailyMinutes) * 100)
        return "Set your first target to \(minutesLabel(for: Int(idealDailyMinutes))) total, with \(socialShare)% of it reserved for social apps. Focus on \(reductionFocus.lowercased()) first, then expand the block list once the habit starts fighting back."
    }

    private var fallbackRecommendedBlockTargets: [String] {
        let focus = reductionFocus.lowercased()
        var targets: [String] = []

        if focus.contains("social") || focus.contains("scroll") {
            targets.append(contentsOf: ["Instagram", "TikTok", "X"])
        }

        if focus.contains("shop") || focus.contains("market") {
            targets.append(contentsOf: ["Vinted", "Amazon", "eBay"])
        }

        if focus.contains("video") {
            targets.append(contentsOf: ["YouTube", "Netflix"])
        }

        return Array(Set(targets)).sorted()
    }

    private var activeRecommendationTitle: String {
        aiRecommendation?.headline ?? "Suggested starting plan"
    }

    private var activeRecommendationSubtitle: String {
        if let aiRecommendation {
            switch aiRecommendation.strictness {
            case .gentle:
                return "AI recommendation • gentle starting plan"
            case .balanced:
                return "AI recommendation • balanced starting plan"
            case .strict:
                return "AI recommendation • strict starting plan"
            }
        }

        return fallbackRecommendationTitle
    }

    private var activeRecommendationBody: String {
        if let aiRecommendation {
            return "\(aiRecommendation.summary) \(aiRecommendation.firstAction)"
        }

        return fallbackRecommendationBody
    }

    private var activeRecommendedBlockTargets: [String] {
        guard let aiRecommendation, !aiRecommendation.recommendedBlockTargets.isEmpty else {
            return fallbackRecommendedBlockTargets
        }

        return aiRecommendation.recommendedBlockTargets
    }

    private var currentRecommendationSignature: String {
        [
            feeling.rawValue,
            reductionFocus.trimmingCharacters(in: .whitespacesAndNewlines),
            String(Int(idealDailyMinutes)),
            String(Int(socialMediaMinutes)),
            String(everythingElseMinutes)
        ].joined(separator: "|")
    }

    private var isRecommendationStale: Bool {
        aiRecommendationSignature != nil && aiRecommendationSignature != currentRecommendationSignature
    }

    private var stepSubtitle: String {
        switch step {
        case .permission:
            return "Give BlockOS permission to do the job."
        case .intake:
            return "Look at your current habits, then decide what normal should be."
        case .configuration:
            return "Choose the apps that should stop being available by default."
        }
    }

    private func makeProfile() -> OnboardingProfile {
        if didSkipIntake {
            return OnboardingProfile(skippedIntake: true)
        }

        return OnboardingProfile(
            skippedIntake: false,
            feeling: feeling,
            goalPlan: ScreenTimeGoalPlan(
                reductionFocus: reductionFocus.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "General distraction" : reductionFocus,
                idealDailyMinutes: Int(idealDailyMinutes),
                socialMediaMinutes: Int(socialMediaMinutes),
                everythingElseMinutes: everythingElseMinutes
            )
        )
    }

    private func clampBreakdown() {
        if socialMediaMinutes > idealDailyMinutes {
            socialMediaMinutes = idealDailyMinutes
        }
    }

    private func markRecommendationStale() {
        aiRecommendationError = nil
    }

    private func refreshAIRecommendation() async {
        guard !didSkipIntake else {
            return
        }

        isLoadingAIRecommendation = true
        defer { isLoadingAIRecommendation = false }

        do {
            aiRecommendation = try await onboardingCoach.recommendation(
                for: OnboardingCoachInput(
                    feeling: feeling,
                    reductionFocus: reductionFocus,
                    idealDailyMinutes: Int(idealDailyMinutes),
                    socialMediaMinutes: Int(socialMediaMinutes),
                    everythingElseMinutes: everythingElseMinutes
                )
            )
            aiRecommendationSignature = currentRecommendationSignature
            aiRecommendationError = nil
        } catch OnboardingCoachError.missingAPIKey {
            aiRecommendation = nil
            aiRecommendationSignature = nil
            aiRecommendationError = nil
        } catch {
            aiRecommendationError = "OpenRouter could not return a recommendation right now. Showing the local BlockOS version instead."
        }
    }

    private func minutesLabel(for minutes: Int) -> String {
        if minutes == 0 {
            return "0m"
        }

        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }

        if minutes > 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes)m"
    }

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

    private func breakdownMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 18))
    }
}

private struct UsageInsightsReportCard: View {
    private let interval = DateInterval(
        start: Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: .now)) ?? Calendar.current.startOfDay(for: .now),
        end: .now
    )

    var body: some View {
        DeviceActivityReport(
            .blockOSOnboarding,
            filter: DeviceActivityFilter(segment: .daily(during: interval))
        )
        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 22))
        .clipShape(RoundedRectangle(cornerRadius: 22))
    }
}

private extension DeviceActivityReport.Context {
    static let blockOSOnboarding = Self("BlockOS Onboarding")
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

private extension OnboardingFeeling {
    var displayName: String {
        switch self {
        case .okay:
            return "Mostly fine, but sloppy"
        case .concerned:
            return "A bit too high"
        case .frustrated:
            return "I keep cheating myself"
        case .overwhelmed:
            return "It feels out of control"
        }
    }
}

private extension RestrictionAuthorizationStatus {
    var displayName: String {
        switch self {
        case .notDetermined:
            return "Waiting for permission"
        case .denied:
            return "Access denied"
        case .approved:
            return "Access enabled"
        }
    }
}
