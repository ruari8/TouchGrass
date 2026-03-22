import BlockOSAppSupport
import BlockOSDomain
import BlockOSEnforcement
import BlockOSPersistence
import Foundation
import Testing

struct SessionCoordinatorTests {
    @Test
    func updatingTheActiveBlockSetPersistsAndReappliesRestrictions() async throws {
        let store = InMemoryAppStateStore()
        let shieldController = NoopShieldController()
        let coordinator = SessionCoordinator(store: store, shieldController: shieldController)
        let initialSet = BlockSet(
            name: "Initial",
            targets: [
                BlockTarget(kind: .application, identifier: "com.example.initial", displayName: "Initial")
            ]
        )
        let updatedSet = BlockSet(
            name: "Updated",
            targets: [
                BlockTarget(kind: .application, identifier: "com.example.updated", displayName: "Updated"),
                BlockTarget(kind: .webDomain, identifier: "example.com", displayName: "Example")
            ]
        )

        _ = try await coordinator.startSession(
            blockSet: initialSet,
            unlockMethods: [.timer120, .qrCode],
            now: Date(timeIntervalSince1970: 100)
        )

        let updatedSession = try await coordinator.updateActiveBlockSet(updatedSet)
        let restoredSession = try await coordinator.restoreActiveSession()
        let lastAppliedBlockSet = await shieldController.lastAppliedBlockSet

        #expect(updatedSession.blockSet == updatedSet)
        #expect(restoredSession?.blockSet == updatedSet)
        #expect(lastAppliedBlockSet == updatedSet)
    }
}
