import Combine
import Foundation
import SwiftUI
import FamilyControls
import BlockOSAppSupport
import BlockOSDomain
import BlockOSEnforcement
import BlockOSPersistence

@MainActor
final class AppContainer: ObservableObject {
    let coordinator: SessionCoordinator
    let store: JSONFileAppStateStore
    private let shieldController: any ShieldControlling
    private let authorizer: any RestrictionAuthorizing
    private let managedShieldController: ManagedSettingsShieldController
    private let dailyLimitMonitor: ScreenTimeDailyLimitMonitor

    @Published private(set) var activeSession: FocusSession?
    @Published private(set) var sessionHistory: [FocusSession] = []
    @Published private(set) var qrTokens: [QRCodeToken] = []
    @Published private(set) var onboardingProfile: OnboardingProfile?
    @Published private(set) var dailyLimitSummary: String?
    @Published private(set) var dailyLimitLockState: DailyLimitLockState = .idle
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoadedInitialState = false
    @Published private(set) var authorizationStatus: RestrictionAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var activitySelection = FamilyActivitySelection()

    init(
        coordinator: SessionCoordinator,
        store: JSONFileAppStateStore,
        shieldController: any ShieldControlling,
        authorizer: any RestrictionAuthorizing,
        managedShieldController: ManagedSettingsShieldController,
        dailyLimitMonitor: ScreenTimeDailyLimitMonitor
    ) {
        self.coordinator = coordinator
        self.store = store
        self.shieldController = shieldController
        self.authorizer = authorizer
        self.managedShieldController = managedShieldController
        self.dailyLimitMonitor = dailyLimitMonitor
    }

    static func bootstrap() -> AppContainer {
        let baseURL = BlockOSSharedContainer.baseURL()
        migrateLegacyStorageIfNeeded(to: baseURL)
        let storeURL = baseURL.appending(path: "state.json")
        let store = JSONFileAppStateStore(fileURL: storeURL)
        let selectionURL = baseURL.appending(path: "activity-selection.json")
        let selectionStore = FamilyActivitySelectionStore(fileURL: selectionURL)
        let shieldController = ManagedSettingsShieldController(selectionStore: selectionStore)
        let authorizer = SystemRestrictionAuthorizer()
        let coordinator = SessionCoordinator(store: store, shieldController: shieldController)
        let dailyLimitMonitor = ScreenTimeDailyLimitMonitor()

        return AppContainer(
            coordinator: coordinator,
            store: store,
            shieldController: shieldController,
            authorizer: authorizer,
            managedShieldController: shieldController,
            dailyLimitMonitor: dailyLimitMonitor
        )
    }

    private static func migrateLegacyStorageIfNeeded(to baseURL: URL) {
        let legacyBaseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "BlockOS")

        guard legacyBaseURL != baseURL else {
            return
        }

        for fileName in ["state.json", "activity-selection.json"] {
            let legacyURL = legacyBaseURL.appending(path: fileName)
            let destinationURL = baseURL.appending(path: fileName)

            guard
                FileManager.default.fileExists(atPath: legacyURL.path),
                !FileManager.default.fileExists(atPath: destinationURL.path)
            else {
                continue
            }

            do {
                try FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)
                try FileManager.default.copyItem(at: legacyURL, to: destinationURL)
            } catch {
                // A failed migration should not prevent the app from starting with a fresh store.
            }
        }
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            authorizationStatus = await authorizer.authorizationStatus()
            activitySelection = try await managedShieldController.loadSelection()
            let state = try await store.load()
            activeSession = state.activeSession
            sessionHistory = state.sessionHistory
            qrTokens = state.qrTokens
            onboardingProfile = state.onboardingProfile
            dailyLimitLockState = DailyLimitLockStore.load()

            if let activeSession {
                try await shieldController.applyRestrictions(for: activeSession.blockSet)
            } else if dailyLimitLockState.isLocked, activitySelection.hasTargets {
                activeSession = try await coordinator.startSession(
                    blockSet: makeBlockSet(from: activitySelection),
                    unlockMethods: [.touchGrassPhoto, .timer120]
                )
            }

            try syncDailyLimitMonitoring()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }

        if !hasLoadedInitialState {
            hasLoadedInitialState = true
        }
    }

    func requestAuthorization() async {
        isLoading = true
        defer { isLoading = false }

        do {
            authorizationStatus = try await authorizer.requestAuthorization()
            do {
                try syncDailyLimitMonitoring()
            } catch {
                errorMessage = "Screen Time access is enabled, but daily limit monitoring could not start: \(error.localizedDescription)"
                return
            }
            errorMessage = nil
        } catch {
            authorizationStatus = await authorizer.authorizationStatus()
            errorMessage = authorizationRequestMessage(for: authorizationStatus)
        }
    }

    func persistSelection(
        _ selection: FamilyActivitySelection,
        previousSelection: FamilyActivitySelection? = nil
    ) async {
        if activeSession != nil {
            let baselineSelection = previousSelection ?? activitySelection

            guard selection.hasTargets else {
                activitySelection = baselineSelection
                errorMessage = "Keep at least one blocked target while a focus session is active."
                return
            }

            guard selection.containsAllTargets(from: baselineSelection) else {
                activitySelection = baselineSelection
                errorMessage = "While focus is active, you can only add more blocked apps or websites. Use Emergency Unblock to remove one."
                return
            }
        }

        do {
            try await managedShieldController.saveSelection(selection)
            activitySelection = selection

            if activeSession != nil {
                activeSession = try await coordinator.updateActiveBlockSet(makeBlockSet(from: selection))
            }

            try syncDailyLimitMonitoring()
            errorMessage = nil
        } catch {
            if let previousSelection {
                activitySelection = previousSelection
            }
            errorMessage = error.localizedDescription
        }
    }

    func startSession() async {
        guard authorizationStatus == .approved else {
            errorMessage = "Grant Family Controls authorization before starting a session."
            return
        }

        guard activitySelection.hasTargets else {
            errorMessage = "Choose at least one app, category, or website to block."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            try await managedShieldController.saveSelection(activitySelection)

            activeSession = try await coordinator.startSession(
                blockSet: makeBlockSet(from: activitySelection),
                unlockMethods: [.touchGrassPhoto, .timer120]
            )
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func beginUnlock(_ method: UnlockMethod) async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeSession = try await coordinator.beginUnlock(method: method)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func markUnlockReady(_ method: UnlockMethod) async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeSession = try await coordinator.markUnlockReady(method: method)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeTimerUnlock() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await coordinator.markUnlockReady(method: .timer120)
            _ = try await coordinator.confirmUnlock()
            try markDailyLimitUnlockedIfNeeded(detail: "Timer unlock completed.")
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeTouchGrassUnlock() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await coordinator.markUnlockReady(method: .touchGrassPhoto)
            _ = try await coordinator.confirmUnlock()
            try markDailyLimitUnlockedIfNeeded(detail: "Touch Grass challenge completed.")
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func confirmUnlock() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await coordinator.confirmUnlock()
            try markDailyLimitUnlockedIfNeeded(detail: "Unlock challenge completed.")
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func cancelUnlock() async {
        isLoading = true
        defer { isLoading = false }

        do {
            activeSession = try await coordinator.cancelUnlock()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func emergencyOverride() async {
        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await coordinator.emergencyOverride()
            try markDailyLimitUnlockedIfNeeded(detail: "Emergency override completed.")
            await refresh()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func generateQRCode(label: String) async {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "QR label cannot be empty."
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            _ = try await coordinator.generateQRCode(label: label)
            qrTokens = try await coordinator.loadQRCodes()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unlockWithQRCode(_ token: QRCodeToken) async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard try await coordinator.markQRCodeScanned(payload: token.payload) != nil else {
                errorMessage = "QR code was not recognized."
                return
            }
            activeSession = try await coordinator.markUnlockReady(method: .qrCode)
            qrTokens = try await coordinator.loadQRCodes()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func completeOnboarding(_ profile: OnboardingProfile) async {
        isLoading = true
        defer { isLoading = false }

        do {
            var state = try await store.load()
            state.onboardingProfile = profile
            try await store.save(state)
            onboardingProfile = profile
            try syncDailyLimitMonitoring()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var hasCompletedOnboarding: Bool {
        onboardingProfile != nil
    }

    var goalPlanSummary: String? {
        guard let goalPlan = onboardingProfile?.goalPlan else {
            return nil
        }

        if !goalPlan.categoryBudgets.isEmpty {
            let categorySummary = goalPlan.categoryBudgets
                .filter { $0.minutes > 0 }
                .prefix(4)
                .map { "\($0.displayName) \(formattedMinutes($0.minutes))" }
                .joined(separator: " • ")

            if categorySummary.isEmpty {
                return "\(formattedMinutes(goalPlan.idealDailyMinutes)) daily"
            }

            return "\(formattedMinutes(goalPlan.idealDailyMinutes)) daily • \(categorySummary)"
        }

        return "\(formattedMinutes(goalPlan.idealDailyMinutes)) daily • \(formattedMinutes(goalPlan.socialMediaMinutes)) social • \(formattedMinutes(goalPlan.everythingElseMinutes)) everything else"
    }

    var selectionSummary: String {
        let appCount = activitySelection.applicationTokens.count
        let categoryCount = activitySelection.categoryTokens.count
        let webDomainCount = activitySelection.webDomainTokens.count

        guard appCount + categoryCount + webDomainCount > 0 else {
            return "No blocked targets selected yet."
        }

        return [
            summaryText(count: appCount, singular: "app"),
            summaryText(count: categoryCount, singular: "category"),
            summaryText(count: webDomainCount, singular: "website")
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " • ")
    }

    func makePreviewTargets() -> [BlockTarget] {
        makeBlockSet(from: activitySelection).targets
    }

    private func makeBlockSet(from selection: FamilyActivitySelection) -> BlockSet {
        var targets: [BlockTarget] = []

        if !selection.applicationTokens.isEmpty {
            targets.append(
                BlockTarget(
                    kind: .application,
                    identifier: "selected-applications",
                    displayName: summaryText(count: selection.applicationTokens.count, singular: "app")
                )
            )
        }

        if !selection.categoryTokens.isEmpty {
            targets.append(
                BlockTarget(
                    kind: .category,
                    identifier: "selected-categories",
                    displayName: summaryText(count: selection.categoryTokens.count, singular: "category")
                )
            )
        }

        if !selection.webDomainTokens.isEmpty {
            targets.append(
                BlockTarget(
                    kind: .webDomain,
                    identifier: "selected-web-domains",
                    displayName: summaryText(count: selection.webDomainTokens.count, singular: "website")
                )
            )
        }

        return BlockSet(name: "Selected Focus Set", targets: targets)
    }

    private func summaryText(count: Int, singular: String) -> String {
        guard count > 0 else {
            return ""
        }

        return count == 1 ? "1 \(singular)" : "\(count) \(singular)s"
    }

    private func formattedMinutes(_ minutes: Int) -> String {
        if minutes % 60 == 0 {
            return "\(minutes / 60)h"
        }

        if minutes > 60 {
            return "\(minutes / 60)h \(minutes % 60)m"
        }

        return "\(minutes)m"
    }

    func clearErrorMessage() {
        errorMessage = nil
    }

    private func syncDailyLimitMonitoring() throws {
        guard hasCompletedOnboarding, authorizationStatus == .approved else {
            dailyLimitSummary = nil
            return
        }

        dailyLimitLockState = DailyLimitLockStore.load()
        dailyLimitSummary = try dailyLimitMonitor.sync(
            selection: activitySelection,
            profile: onboardingProfile,
            lockState: dailyLimitLockState
        )
    }

    private func markDailyLimitUnlockedIfNeeded(detail: String) throws {
        guard DailyLimitLockStore.load().isLocked else {
            return
        }

        dailyLimitMonitor.clearLimitShield()
        try DailyLimitLockStore.save(.unlocked(detail: detail))
    }

    private func authorizationRequestMessage(for status: RestrictionAuthorizationStatus) -> String {
        switch status {
        case .approved:
            return "Screen Time access could not be confirmed. Please try again."
        case .denied:
            return "Screen Time access was not granted. To block apps, allow access and try again."
        case .notDetermined:
            return "Screen Time access was not granted. You can try again when you're ready."
        }
    }
}

private extension FamilyActivitySelection {
    var hasTargets: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }

    func containsAllTargets(from other: FamilyActivitySelection) -> Bool {
        applicationTokens.isSuperset(of: other.applicationTokens)
            && categoryTokens.isSuperset(of: other.categoryTokens)
            && webDomainTokens.isSuperset(of: other.webDomainTokens)
    }
}
