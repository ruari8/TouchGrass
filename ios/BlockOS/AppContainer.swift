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

    @Published private(set) var activeSession: FocusSession?
    @Published private(set) var sessionHistory: [FocusSession] = []
    @Published private(set) var qrTokens: [QRCodeToken] = []
    @Published private(set) var isLoading = false
    @Published private(set) var authorizationStatus: RestrictionAuthorizationStatus = .notDetermined
    @Published var errorMessage: String?
    @Published var activitySelection = FamilyActivitySelection()

    init(
        coordinator: SessionCoordinator,
        store: JSONFileAppStateStore,
        shieldController: any ShieldControlling,
        authorizer: any RestrictionAuthorizing,
        managedShieldController: ManagedSettingsShieldController
    ) {
        self.coordinator = coordinator
        self.store = store
        self.shieldController = shieldController
        self.authorizer = authorizer
        self.managedShieldController = managedShieldController
    }

    static func bootstrap() -> AppContainer {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "BlockOS")
        let storeURL = baseURL.appending(path: "state.json")
        let store = JSONFileAppStateStore(fileURL: storeURL)
        let selectionURL = baseURL.appending(path: "activity-selection.json")
        let selectionStore = FamilyActivitySelectionStore(fileURL: selectionURL)
        let shieldController = ManagedSettingsShieldController(selectionStore: selectionStore)
        let authorizer = SystemRestrictionAuthorizer()
        let coordinator = SessionCoordinator(store: store, shieldController: shieldController)

        return AppContainer(
            coordinator: coordinator,
            store: store,
            shieldController: shieldController,
            authorizer: authorizer,
            managedShieldController: shieldController
        )
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        do {
            authorizationStatus = await authorizer.authorizationStatus()
            activitySelection = try await managedShieldController.loadSelection()
            activeSession = try await coordinator.restoreActiveSession()
            sessionHistory = try await coordinator.loadHistory()
            qrTokens = try await coordinator.loadQRCodes()

            if let activeSession {
                try await shieldController.applyRestrictions(for: activeSession.blockSet)
            }

            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func requestAuthorization() async {
        isLoading = true
        defer { isLoading = false }

        do {
            authorizationStatus = try await authorizer.requestAuthorization()
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func persistSelection(_ selection: FamilyActivitySelection) async {
        do {
            try await managedShieldController.saveSelection(selection)
            activitySelection = selection
            errorMessage = nil
        } catch {
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
                unlockMethods: [.timer120, .qrCode]
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
}

private extension FamilyActivitySelection {
    var hasTargets: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }
}
