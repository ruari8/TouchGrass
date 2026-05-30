import BlockOSDomain
import Testing
import Foundation

struct FocusSessionEngineTests {
    private let engine = FocusSessionEngine()

    @Test
    func sessionCompletesAfterTimerUnlock() throws {
        let blockSet = BlockSet(
            name: "Work Apps",
            targets: [
                BlockTarget(kind: .application, identifier: "com.example.social", displayName: "Social")
            ]
        )
        let start = Date(timeIntervalSince1970: 100)

        let armed = engine.armSession(
            blockSet: blockSet,
            allowedUnlockMethods: [.timer120],
            now: start
        )
        #expect(armed.state == .arming)

        let active = try engine.activate(armed, now: start)
        #expect(active.state == .activeBlocked)

        let unlockStarted = try engine.beginUnlock(active, method: .timer120, now: start.addingTimeInterval(10))
        #expect(unlockStarted.state == .unlockChallengeInProgress)

        let unlockReady = try engine.markUnlockReady(
            unlockStarted,
            method: .timer120,
            now: start.addingTimeInterval(130)
        )
        #expect(unlockReady.state == .unlockPending)

        let unlocked = try engine.confirmUnlock(unlockReady, now: start.addingTimeInterval(131))
        #expect(unlocked.state == .unlockedGrace)
        #expect(unlocked.unlockHistory.count == 1)
        #expect(unlocked.unlockHistory.first?.outcome == .succeeded)

        let completed = try engine.completeSession(unlocked, now: start.addingTimeInterval(132))
        #expect(completed.state == .completed)
        #expect(completed.endedAt == start.addingTimeInterval(132))
    }

    @Test
    func invalidUnlockMethodIsRejected() throws {
        let blockSet = BlockSet(name: "Default", targets: [])
        let session = try engine.activate(
            engine.armSession(blockSet: blockSet, allowedUnlockMethods: [.timer120]),
            now: .now
        )

        #expect(throws: SessionTransitionError.self) {
            try engine.beginUnlock(session, method: .qrCode)
        }
    }

    @Test
    func touchGrassPhotoUnlockCompletesSession() throws {
        let blockSet = BlockSet(name: "Default", targets: [])
        let start = Date(timeIntervalSince1970: 150)
        let active = try engine.activate(
            engine.armSession(blockSet: blockSet, allowedUnlockMethods: [.touchGrassPhoto], now: start),
            now: start
        )

        let unlock = try engine.beginUnlock(active, method: .touchGrassPhoto, now: start.addingTimeInterval(10))
        let ready = try engine.markUnlockReady(unlock, method: .touchGrassPhoto, now: start.addingTimeInterval(60))
        let unlocked = try engine.confirmUnlock(ready, now: start.addingTimeInterval(61))
        let completed = try engine.completeSession(unlocked, now: start.addingTimeInterval(62))

        #expect(completed.state == .completed)
        #expect(completed.unlockHistory.first?.method == .touchGrassPhoto)
        #expect(completed.unlockHistory.first?.outcome == .succeeded)
    }

    @Test
    func emergencyOverrideEndsSession() throws {
        let blockSet = BlockSet(name: "Default", targets: [])
        let start = Date(timeIntervalSince1970: 200)
        let active = try engine.activate(
            engine.armSession(blockSet: blockSet, allowedUnlockMethods: [.timer120, .qrCode], now: start),
            now: start
        )
        let unlock = try engine.beginUnlock(active, method: .qrCode, now: start.addingTimeInterval(5))

        let overridden = try engine.emergencyOverride(unlock, now: start.addingTimeInterval(6))
        #expect(overridden.state == .abortedEmergencyOverride)
        #expect(overridden.endedAt == start.addingTimeInterval(6))
        #expect(overridden.unlockHistory.count == 1)
        #expect(overridden.unlockHistory.first?.outcome == .emergencyOverride)
    }
}
