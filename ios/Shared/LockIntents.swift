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
    /// A Shortcut saved with a list that has since been deleted still resolves, so `LockIntent`
    /// can say the list is gone instead of the Shortcut failing before it runs.
    func entities(for identifiers: [UUID]) async throws -> [BlockListEntity] {
        let existing = try await suggestedEntities()
        return identifiers.map { id in
            existing.first { $0.id == id } ?? BlockListEntity(id: id, name: "Deleted Block List")
        }
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
        do {
            let list = try LockActions.lock(blockListID: blockList?.id)
            return .result(dialog: "\(list.name) is Locked. Go touch grass to get out.")
        } catch LockActions.LockError.blockListMissing {
            return .result(dialog: "That Block List no longer exists. Edit the Shortcut to choose another.")
        } catch LockActions.LockError.notSetUp {
            return .result(dialog: "Set up Touch Grass first.")
        }
    }
}

/// Where `OpenTouchGrassIntent` takes the user. Controls can only open the app through an
/// `OpenIntent`, which needs a destination.
enum AppDestination: String, AppEnum {
    case touchGrass

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Destination"
    static let caseDisplayRepresentations: [AppDestination: DisplayRepresentation] = [.touchGrass: "Touch Grass camera"]
}

/// Opens Touch Grass on the camera.
struct OpenTouchGrassIntent: OpenIntent {
    static let title: LocalizedStringResource = "Touch Grass"
    static let description = IntentDescription("Opens the camera to take a photo of grass and unlock.")

    @Parameter(title: "Destination", default: .touchGrass)
    var target: AppDestination

    func perform() async throws -> some IntentResult {
        LockActions.requestTouchGrass()
        return .result()
    }
}
