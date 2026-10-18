#if DEBUG
import Foundation
import TouchGrassCore

/// Launch with `-demo locked`, `-demo break` or `-demo unlocked` to skip setup with sample data,
/// and `-demoTab rules` to open on the Rules tab, for simulator screenshots. Debug builds only.
enum DemoState {
    static var initialTab: String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demoTab"), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    static func apply(to store: AppStateStore) {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-demo"), arguments.indices.contains(index + 1) else { return }
        let scenario = arguments[index + 1]
        let now = Date()
        _ = try? store.update { state in
            let social = BlockList(name: "Social", itemCount: 6)
            let everything = BlockList(name: "Everything", itemCount: 14)
            let bedtime = Schedule(name: "Bedtime", blockListID: everything.id, start: TimeOfDay(hour: 22), end: TimeOfDay(hour: 7))
            let mornings = Schedule(name: "Mornings", blockListID: social.id, start: TimeOfDay(hour: 7), end: TimeOfDay(hour: 9), weekdays: [2, 3, 4, 5, 6])
            let budget = Budget(name: "Social", blockListID: social.id, minutes: 60)
            state = AppState(hasCompletedSetup: true, blockLists: [social, everything], schedules: [bedtime, mornings], budgets: [budget], grassCount: 12)
            state.settings.defaultBlockListID = social.id
            try? state.emergencyUnlocks.use(at: now.addingTimeInterval(-12 * 24 * 60 * 60))
            switch scenario {
            case "locked":
                state.startManualLock(blockListID: social.id, at: now)
                state.startAutomaticLock(source: .schedule(bedtime.id), blockListID: everything.id, endsAt: now.addingTimeInterval(8 * 60 * 60), at: now)
            case "break":
                state.startAutomaticLock(source: .schedule(bedtime.id), blockListID: everything.id, endsAt: now.addingTimeInterval(8 * 60 * 60), at: now)
                state.touchGrass(at: now.addingTimeInterval(-4 * 60))
            default:
                break
            }
        }
    }
}
#endif
