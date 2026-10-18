#if os(iOS)
import Foundation
import TouchGrassCore

/// Lock and unlock requests from outside the app's screens: Control Center, the Lock Screen,
/// the Action button and Shortcuts. They may run in the widget extension's process, so they go
/// straight to the shared store and shields rather than through the app's model.
public enum LockActions {
    /// Starts a Manual Lock on a Block List, or the default one. Returns the list that was locked.
    @discardableResult
    public static func lock(blockListID: UUID? = nil, store: AppStateStore = AppStateStore(), at now: Date = .now) throws -> BlockList? {
        var locked: BlockList?
        let state = try store.update({ state in
            state.reconcile(at: now)
            guard let list = blockListID.flatMap(state.blockList(id:)) ?? state.defaultBlockList else { return }
            state.startManualLock(blockListID: list.id, at: now)
            locked = list
        }, whileLocked: { Enforcement.applyShields(for: $0, at: now) })
        Enforcement.scheduleBackgroundWork(for: state, at: now)
        return locked
    }

    /// Asks the app to open on the Touch Grass camera next time it comes to the foreground.
    public static func requestTouchGrass() {
        AppGroup.defaults.set(true, forKey: openTouchGrassKey)
    }

    /// Whether something asked to open the camera, clearing the request.
    public static func takeTouchGrassRequest() -> Bool {
        defer { AppGroup.defaults.removeObject(forKey: openTouchGrassKey) }
        return AppGroup.defaults.bool(forKey: openTouchGrassKey)
    }

    private static let openTouchGrassKey = "openTouchGrass"
}
#endif
