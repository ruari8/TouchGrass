import AppIntents
import Foundation
import TouchGrassCore
import TouchGrassScreenTime

/// A Block List, for choosing which list a Shortcut or control locks.
struct BlockListEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Block List"
    static let defaultQuery = BlockListQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct BlockListQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BlockListEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BlockListEntity] {
        try AppStateStore().load().blockLists.map { BlockListEntity(id: $0.id, name: $0.name) }
    }
}

/// Starts a Manual Lock. Used by the Lock control (Control Center, Lock Screen, Action button)
/// and by Shortcuts, including location automations such as "When I arrive at work".
struct LockIntent: AppIntent {
    static let title: LocalizedStringResource = "Lock"
    static let description = IntentDescription("Starts a Manual Lock. It lasts until you touch grass.")

    @Parameter(title: "Block List", description: "Leave empty to lock your default Block List.")
    var blockList: BlockListEntity?

    init() {}

    init(blockList: BlockListEntity?) {
        self.blockList = blockList
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let list = try LockActions.lock(blockListID: blockList?.id) else {
            return .result(dialog: "Set up Touch Grass first.")
        }
        return .result(dialog: "\(list.name) is Locked. Go touch grass to get out.")
    }
}

/// Opens Touch Grass on the camera.
struct OpenTouchGrassIntent: AppIntent {
    static let title: LocalizedStringResource = "Touch Grass"
    static let description = IntentDescription("Opens the camera to take a photo of grass and unlock.")
    static let supportedModes: IntentModes = .foreground

    func perform() async throws -> some IntentResult {
        LockActions.requestTouchGrass()
        return .result()
    }
}
