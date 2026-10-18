#if os(iOS)
import Foundation
import TouchGrassCore

/// Lock and unlock requests from outside the app's screens: Control Center, the Lock Screen,
/// the Action button and Shortcuts. They may run in the widget extension's process, so they go
/// straight to the shared store and shields rather than through the app's model.
public enum LockActions {
    public enum LockError: Error {
        case notSetUp
        /// A Shortcut asked for a Block List that has since been deleted.
        case blockListMissing
    }

    /// Starts a Manual Lock on a Block List, or the default one if none is given. Returns the list that was locked.
    @discardableResult
    public static func lock(blockListID: UUID? = nil, store: AppStateStore = AppStateStore(), at now: Date = .now) throws -> BlockList {
        var locked: BlockList?
        try store.update({ state in
            state.reconcile(at: now)
            let list: BlockList?
            if let blockListID {
                guard let chosen = state.blockList(id: blockListID) else { throw LockError.blockListMissing }
                list = chosen
            } else {
                list = state.defaultBlockList
            }
            guard state.hasCompletedSetup, let list else { throw LockError.notSetUp }
            state.startManualLock(blockListID: list.id, at: now)
            locked = list
        }, whileLocked: { Enforcement.applyShields(for: $0, at: now) })
        Enforcement.scheduleBackgroundWork(using: store, at: now)
        StateChangeSignal.post()
        guard let locked else { throw LockError.notSetUp }
        return locked
    }

    /// Asks the app to open on the Touch Grass camera next time it comes to the foreground.
    public static func requestTouchGrass() {
        AppGroup.defaults.set(true, forKey: openTouchGrassKey)
        StateChangeSignal.post()
    }

    /// Whether something asked to open the camera, clearing the request.
    public static func takeTouchGrassRequest() -> Bool {
        defer { AppGroup.defaults.removeObject(forKey: openTouchGrassKey) }
        return AppGroup.defaults.bool(forKey: openTouchGrassKey)
    }

    private static let openTouchGrassKey = "openTouchGrass"
}
#endif
