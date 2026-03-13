import Foundation

public struct BlockTarget: Codable, Hashable, Sendable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case application
        case category
        case webDomain
    }

    public let id: UUID
    public let kind: Kind
    public let identifier: String
    public let displayName: String

    public init(
        id: UUID = UUID(),
        kind: Kind,
        identifier: String,
        displayName: String
    ) {
        self.id = id
        self.kind = kind
        self.identifier = identifier
        self.displayName = displayName
    }
}

public struct BlockSet: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var name: String
    public var targets: [BlockTarget]

    public init(id: UUID = UUID(), name: String, targets: [BlockTarget]) {
        self.id = id
        self.name = name
        self.targets = targets
    }
}

public enum UnlockMethod: String, Codable, CaseIterable, Sendable {
    case timer120
    case qrCode
}

public enum FocusSessionState: String, Codable, Sendable {
    case idle
    case arming
    case activeBlocked
    case unlockChallengeInProgress
    case unlockPending
    case unlockedGrace
    case completed
    case abortedEmergencyOverride
}

public enum UnlockAttemptOutcome: String, Codable, Sendable {
    case succeeded
    case cancelled
    case failed
    case emergencyOverride
}

public struct UnlockAttempt: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let method: UnlockMethod
    public let startedAt: Date
    public let finishedAt: Date
    public let outcome: UnlockAttemptOutcome
    public let detail: String

    public init(
        id: UUID = UUID(),
        method: UnlockMethod,
        startedAt: Date,
        finishedAt: Date,
        outcome: UnlockAttemptOutcome,
        detail: String
    ) {
        self.id = id
        self.method = method
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.detail = detail
    }
}

public struct OverridePolicy: Codable, Hashable, Sendable {
    public var allowsEmergencyOverride: Bool
    public var requiresSecondaryConfirmation: Bool

    public init(
        allowsEmergencyOverride: Bool = true,
        requiresSecondaryConfirmation: Bool = true
    ) {
        self.allowsEmergencyOverride = allowsEmergencyOverride
        self.requiresSecondaryConfirmation = requiresSecondaryConfirmation
    }
}

public struct QRCodeToken: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public var label: String
    public var payload: String
    public let createdAt: Date
    public var lastScannedAt: Date?

    public init(
        id: UUID = UUID(),
        label: String,
        payload: String,
        createdAt: Date = .now,
        lastScannedAt: Date? = nil
    ) {
        self.id = id
        self.label = label
        self.payload = payload
        self.createdAt = createdAt
        self.lastScannedAt = lastScannedAt
    }
}

public struct FocusSession: Codable, Hashable, Sendable, Identifiable {
    public let id: UUID
    public let blockSet: BlockSet
    public let startedAt: Date
    public var state: FocusSessionState
    public var allowedUnlockMethods: [UnlockMethod]
    public var overridePolicy: OverridePolicy
    public var activeUnlockMethod: UnlockMethod?
    public var activeUnlockStartedAt: Date?
    public var pendingUnlockConfirmedAt: Date?
    public var endedAt: Date?
    public var unlockHistory: [UnlockAttempt]

    public init(
        id: UUID = UUID(),
        blockSet: BlockSet,
        startedAt: Date,
        state: FocusSessionState,
        allowedUnlockMethods: [UnlockMethod],
        overridePolicy: OverridePolicy,
        activeUnlockMethod: UnlockMethod? = nil,
        activeUnlockStartedAt: Date? = nil,
        pendingUnlockConfirmedAt: Date? = nil,
        endedAt: Date? = nil,
        unlockHistory: [UnlockAttempt] = []
    ) {
        self.id = id
        self.blockSet = blockSet
        self.startedAt = startedAt
        self.state = state
        self.allowedUnlockMethods = allowedUnlockMethods
        self.overridePolicy = overridePolicy
        self.activeUnlockMethod = activeUnlockMethod
        self.activeUnlockStartedAt = activeUnlockStartedAt
        self.pendingUnlockConfirmedAt = pendingUnlockConfirmedAt
        self.endedAt = endedAt
        self.unlockHistory = unlockHistory
    }
}

public enum SessionTransitionError: Error, Equatable, CustomStringConvertible {
    case invalidState(expected: [FocusSessionState], actual: FocusSessionState)
    case unlockMethodNotAllowed(UnlockMethod)
    case noActiveUnlockMethod
    case unlockMethodMismatch(expected: UnlockMethod, actual: UnlockMethod)
    case emergencyOverrideDisabled

    public var description: String {
        switch self {
        case let .invalidState(expected, actual):
            return "Invalid state. Expected one of \(expected.map { $0.rawValue }), got \(actual.rawValue)."
        case let .unlockMethodNotAllowed(method):
            return "Unlock method not allowed: \(method.rawValue)."
        case .noActiveUnlockMethod:
            return "No active unlock method is in progress."
        case let .unlockMethodMismatch(expected, actual):
            return "Unlock method mismatch. Expected \(expected.rawValue), got \(actual.rawValue)."
        case .emergencyOverrideDisabled:
            return "Emergency override is disabled by policy."
        }
    }
}
