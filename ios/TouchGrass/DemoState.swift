#if DEBUG
import Foundation
import TouchGrassCore

/// Launch with `-demo locked`, `-demo break` or `-demo unlocked` to skip setup with sample data,
/// for simulator screenshots. Debug builds only.
enum DemoState {
    static func apply(to store: AppStateStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo"), arguments.indices.contains(index + 1) else { return }
        let scenario = arguments[index + 1]
        let now = Date()
        store.update { state in
            let social = BlockList(name: "Social", itemCount: 6)
            let everything = BlockList(name: "Everything", itemCount: 14)
            state = AppState(hasCompletedSetup: true, blockLists: [social, everything], grassCount: 12)
            state.settings.defaultBlockListID = social.id
            try? state.emergencyUnlocks.use(at: now.addingTimeInterval(-12 * 24 * 60 * 60))
            switch scenario {
            case "locked":
                state.startManualLock(blockListID: social.id, at: now)
                state.startAutomaticLock(source: .schedule(UUID()), blockListID: everything.id, endsAt: now.addingTimeInterval(8 * 60 * 60), at: now)
            case "break":
                state.startAutomaticLock(source: .schedule(UUID()), blockListID: everything.id, endsAt: now.addingTimeInterval(8 * 60 * 60), at: now)
                state.touchGrass(at: now.addingTimeInterval(-4 * 60))
            default:
                break
            }
        }
    }
}
#endif
