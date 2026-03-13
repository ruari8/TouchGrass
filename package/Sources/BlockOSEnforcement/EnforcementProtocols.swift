import BlockOSDomain
import Foundation

public enum RestrictionAuthorizationStatus: String, Sendable {
    case notDetermined
    case denied
    case approved
}

public protocol RestrictionAuthorizing: Sendable {
    func authorizationStatus() async -> RestrictionAuthorizationStatus
    func requestAuthorization() async throws -> RestrictionAuthorizationStatus
}

public protocol ShieldControlling: Sendable {
    func applyRestrictions(for blockSet: BlockSet) async throws
    func clearRestrictions() async throws
}

public actor NoopRestrictionAuthorizer: RestrictionAuthorizing {
    private var status: RestrictionAuthorizationStatus

    public init(status: RestrictionAuthorizationStatus = .notDetermined) {
        self.status = status
    }

    public func authorizationStatus() async -> RestrictionAuthorizationStatus {
        status
    }

    public func requestAuthorization() async throws -> RestrictionAuthorizationStatus {
        status = .approved
        return status
    }
}

public actor NoopShieldController: ShieldControlling {
    public private(set) var lastAppliedBlockSet: BlockSet?

    public init() {}

    public func applyRestrictions(for blockSet: BlockSet) async throws {
        lastAppliedBlockSet = blockSet
    }

    public func clearRestrictions() async throws {
        lastAppliedBlockSet = nil
    }
}
