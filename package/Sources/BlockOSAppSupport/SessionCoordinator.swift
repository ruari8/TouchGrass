import BlockOSDomain
import BlockOSEnforcement
import BlockOSPersistence
import Foundation

public actor SessionCoordinator {
    private let engine: FocusSessionEngine
    private let store: AppStateStore
    private let shieldController: ShieldControlling

    public init(
        engine: FocusSessionEngine = FocusSessionEngine(),
        store: AppStateStore,
        shieldController: ShieldControlling
    ) {
        self.engine = engine
        self.store = store
        self.shieldController = shieldController
    }

    @discardableResult
    public func startSession(
        blockSet: BlockSet,
        unlockMethods: [UnlockMethod],
        overridePolicy: OverridePolicy = OverridePolicy(),
        now: Date = .now
    ) async throws -> FocusSession {
        let armedSession = engine.armSession(
            blockSet: blockSet,
            allowedUnlockMethods: unlockMethods,
            overridePolicy: overridePolicy,
            now: now
        )
        let activeSession = try engine.activate(armedSession, now: now)

        var state = try await store.load()
        state.activeSession = activeSession
        try await store.save(state)
        try await shieldController.applyRestrictions(for: blockSet)
        return activeSession
    }

    @discardableResult
    public func beginUnlock(method: UnlockMethod, now: Date = .now) async throws -> FocusSession {
        var state = try await store.load()
        guard let session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        let updatedSession = try engine.beginUnlock(session, method: method, now: now)
        state.activeSession = updatedSession
        try await store.save(state)
        return updatedSession
    }

    @discardableResult
    public func markUnlockReady(method: UnlockMethod, now: Date = .now) async throws -> FocusSession {
        var state = try await store.load()
        guard let session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        let updatedSession = try engine.markUnlockReady(session, method: method, now: now)
        state.activeSession = updatedSession
        try await store.save(state)
        return updatedSession
    }

    @discardableResult
    public func confirmUnlock(now: Date = .now) async throws -> FocusSession {
        var state = try await store.load()
        guard let session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        var updatedSession = try engine.confirmUnlock(session, now: now)
        try await shieldController.clearRestrictions()
        updatedSession = try engine.completeSession(updatedSession, now: now)

        state.activeSession = nil
        state.sessionHistory.append(updatedSession)
        try await store.save(state)
        return updatedSession
    }

    @discardableResult
    public func cancelUnlock(now: Date = .now, detail: String = "Unlock cancelled by user.") async throws -> FocusSession {
        var state = try await store.load()
        guard let session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        let updatedSession = try engine.cancelUnlock(session, now: now, detail: detail)
        state.activeSession = updatedSession
        try await store.save(state)
        return updatedSession
    }

    @discardableResult
    public func failUnlock(now: Date = .now, detail: String = "Unlock failed.") async throws -> FocusSession {
        var state = try await store.load()
        guard let session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        let updatedSession = try engine.failUnlock(session, now: now, detail: detail)
        state.activeSession = updatedSession
        try await store.save(state)
        return updatedSession
    }

    @discardableResult
    public func emergencyOverride(now: Date = .now) async throws -> FocusSession {
        var state = try await store.load()
        guard let session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        let updatedSession = try engine.emergencyOverride(session, now: now)
        try await shieldController.clearRestrictions()

        state.activeSession = nil
        state.sessionHistory.append(updatedSession)
        try await store.save(state)
        return updatedSession
    }

    public func restoreActiveSession() async throws -> FocusSession? {
        let state = try await store.load()
        return state.activeSession
    }

    @discardableResult
    public func updateActiveBlockSet(_ blockSet: BlockSet) async throws -> FocusSession {
        var state = try await store.load()
        guard var session = state.activeSession else {
            throw CoordinatorError.noActiveSession
        }

        session.blockSet = blockSet
        state.activeSession = session
        try await store.save(state)
        try await shieldController.applyRestrictions(for: blockSet)
        return session
    }

    public func generateQRCode(label: String, now: Date = .now) async throws -> QRCodeToken {
        var state = try await store.load()
        let payload = "blockos://unlock/\(UUID().uuidString.lowercased())"
        let token = QRCodeToken(label: label, payload: payload, createdAt: now)
        state.qrTokens.append(token)
        try await store.save(state)
        return token
    }

    public func markQRCodeScanned(payload: String, now: Date = .now) async throws -> QRCodeToken? {
        var state = try await store.load()
        guard let index = state.qrTokens.firstIndex(where: { $0.payload == payload }) else {
            return nil
        }

        state.qrTokens[index].lastScannedAt = now
        let token = state.qrTokens[index]
        try await store.save(state)
        return token
    }

    public func loadHistory() async throws -> [FocusSession] {
        let state = try await store.load()
        return state.sessionHistory
    }

    public func loadQRCodes() async throws -> [QRCodeToken] {
        let state = try await store.load()
        return state.qrTokens
    }
}

public enum CoordinatorError: Error, Equatable {
    case noActiveSession
}
