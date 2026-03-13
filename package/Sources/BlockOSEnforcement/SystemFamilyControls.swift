#if os(iOS)
import BlockOSDomain
import FamilyControls
import Foundation
import ManagedSettings

public enum FamilyControlsSelectionStoreError: Error, Equatable {
    case emptySelection
}

public final class FamilyActivitySelectionStore: @unchecked Sendable {
    private let fileURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    public init(fileURL: URL) {
        self.fileURL = fileURL

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder
        self.decoder = JSONDecoder()
    }

    public func load() throws -> FamilyActivitySelection {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return FamilyActivitySelection()
        }

        let data = try Data(contentsOf: fileURL)
        return try decoder.decode(FamilyActivitySelection.self, from: data)
    }

    public func save(_ selection: FamilyActivitySelection) throws {
        let directoryURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(selection)
        try data.write(to: fileURL, options: .atomic)
    }
}

public actor SystemRestrictionAuthorizer: RestrictionAuthorizing {
    public init() {}

    public func authorizationStatus() async -> RestrictionAuthorizationStatus {
        mapStatus(AuthorizationCenter.shared.authorizationStatus)
    }

    public func requestAuthorization() async throws -> RestrictionAuthorizationStatus {
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
        return mapStatus(AuthorizationCenter.shared.authorizationStatus)
    }

    private func mapStatus(_ status: AuthorizationStatus) -> RestrictionAuthorizationStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .denied:
            .denied
        case .approved:
            .approved
        @unknown default:
            .denied
        }
    }
}

public actor ManagedSettingsShieldController: ShieldControlling {
    private let store: ManagedSettingsStore
    private let selectionStore: FamilyActivitySelectionStore

    public init(selectionStore: FamilyActivitySelectionStore) {
        self.store = ManagedSettingsStore()
        self.selectionStore = selectionStore
    }

    public func loadSelection() async throws -> FamilyActivitySelection {
        try selectionStore.load()
    }

    public func saveSelection(_ selection: FamilyActivitySelection) async throws {
        try selectionStore.save(selection)
    }

    public func applyRestrictions(for blockSet: BlockSet) async throws {
        let selection = try selectionStore.load()
        guard selection.isNotEmpty else {
            throw FamilyControlsSelectionStoreError.emptySelection
        }

        store.shield.applications = selection.applicationTokens.isEmpty ? nil : selection.applicationTokens
        store.shield.applicationCategories = selection.categoryTokens.isEmpty ? nil : .specific(selection.categoryTokens)
        store.shield.webDomains = selection.webDomainTokens.isEmpty ? nil : selection.webDomainTokens
    }

    public func clearRestrictions() async throws {
        store.clearAllSettings()
    }
}

private extension FamilyActivitySelection {
    var isNotEmpty: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }
}
#endif