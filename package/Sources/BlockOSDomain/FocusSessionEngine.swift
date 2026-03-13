import Foundation

public struct FocusSessionEngine: Sendable {
    public init() {}

    public func armSession(
        blockSet: BlockSet,
        allowedUnlockMethods: [UnlockMethod],
        overridePolicy: OverridePolicy = OverridePolicy(),
        now: Date = .now
    ) -> FocusSession {
        FocusSession(
            blockSet: blockSet,
            startedAt: now,
            state: .arming,
            allowedUnlockMethods: allowedUnlockMethods,
            overridePolicy: overridePolicy
        )
    }

    public func activate(
        _ session: FocusSession,
        now: Date = .now
    ) throws -> FocusSession {
        try transition(session, allowedStates: [.arming]) { current in
            var updated = current
            updated.state = .activeBlocked
            updated.activeUnlockMethod = nil
            updated.activeUnlockStartedAt = nil
            updated.pendingUnlockConfirmedAt = nil
            updated.endedAt = nil
            return updated
        }
    }

    public func beginUnlock(
        _ session: FocusSession,
        method: UnlockMethod,
        now: Date = .now
    ) throws -> FocusSession {
        guard session.allowedUnlockMethods.contains(method) else {
            throw SessionTransitionError.unlockMethodNotAllowed(method)
        }

        return try transition(session, allowedStates: [.activeBlocked]) { current in
            var updated = current
            updated.state = .unlockChallengeInProgress
            updated.activeUnlockMethod = method
            updated.activeUnlockStartedAt = now
            updated.pendingUnlockConfirmedAt = nil
            return updated
        }
    }

    public func markUnlockReady(
        _ session: FocusSession,
        method: UnlockMethod,
        now: Date = .now
    ) throws -> FocusSession {
        try transition(session, allowedStates: [.unlockChallengeInProgress]) { current in
            guard let activeMethod = current.activeUnlockMethod else {
                throw SessionTransitionError.noActiveUnlockMethod
            }
            guard activeMethod == method else {
                throw SessionTransitionError.unlockMethodMismatch(expected: activeMethod, actual: method)
            }

            var updated = current
            updated.state = .unlockPending
            updated.pendingUnlockConfirmedAt = now
            return updated
        }
    }

    public func confirmUnlock(
        _ session: FocusSession,
        now: Date = .now
    ) throws -> FocusSession {
        try transition(session, allowedStates: [.unlockPending]) { current in
            var updated = current
            updated.state = .unlockedGrace
            return updated.recordAttempt(now: now, outcome: .succeeded, detail: "Unlock confirmed.")
        }
    }

    public func cancelUnlock(
        _ session: FocusSession,
        now: Date = .now,
        detail: String = "Unlock cancelled by user."
    ) throws -> FocusSession {
        try transition(session, allowedStates: [.unlockChallengeInProgress, .unlockPending]) { current in
            var updated = current
            updated.state = .activeBlocked
            return updated.recordAttempt(now: now, outcome: .cancelled, detail: detail)
        }
    }

    public func failUnlock(
        _ session: FocusSession,
        now: Date = .now,
        detail: String = "Unlock attempt failed."
    ) throws -> FocusSession {
        try transition(session, allowedStates: [.unlockChallengeInProgress, .unlockPending]) { current in
            var updated = current
            updated.state = .activeBlocked
            return updated.recordAttempt(now: now, outcome: .failed, detail: detail)
        }
    }

    public func completeSession(
        _ session: FocusSession,
        now: Date = .now
    ) throws -> FocusSession {
        try transition(session, allowedStates: [.unlockedGrace]) { current in
            var updated = current
            updated.state = .completed
            updated.endedAt = now
            updated.activeUnlockMethod = nil
            updated.activeUnlockStartedAt = nil
            updated.pendingUnlockConfirmedAt = nil
            return updated
        }
    }

    public func emergencyOverride(
        _ session: FocusSession,
        now: Date = .now,
        detail: String = "Emergency override invoked."
    ) throws -> FocusSession {
        guard session.overridePolicy.allowsEmergencyOverride else {
            throw SessionTransitionError.emergencyOverrideDisabled
        }

        return try transition(
            session,
            allowedStates: [.activeBlocked, .unlockChallengeInProgress, .unlockPending]
        ) { current in
            var updated = current
            updated.state = .abortedEmergencyOverride
            updated.endedAt = now
            return updated.recordAttempt(now: now, outcome: .emergencyOverride, detail: detail)
        }
    }

    private func transition(
        _ session: FocusSession,
        allowedStates: [FocusSessionState],
        body: (FocusSession) throws -> FocusSession
    ) throws -> FocusSession {
        guard allowedStates.contains(session.state) else {
            throw SessionTransitionError.invalidState(expected: allowedStates, actual: session.state)
        }
        return try body(session)
    }
}

private extension FocusSession {
    func recordAttempt(
        now: Date,
        outcome: UnlockAttemptOutcome,
        detail: String
    ) -> FocusSession {
        guard let method = activeUnlockMethod, let startedAt = activeUnlockStartedAt else {
            return self
        }

        var updated = self
        updated.unlockHistory.append(
            UnlockAttempt(
                method: method,
                startedAt: startedAt,
                finishedAt: now,
                outcome: outcome,
                detail: detail
            )
        )
        updated.activeUnlockMethod = nil
        updated.activeUnlockStartedAt = nil
        updated.pendingUnlockConfirmedAt = nil
        return updated
    }
}
