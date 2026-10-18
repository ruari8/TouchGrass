import Foundation

extension AppState {
    /// A short phrase naming what started a Lock, such as "a Manual Lock".
    public func reason(for lock: Lock) -> String {
        switch lock.source {
        case .manual:
            "a Manual Lock"
        case let .schedule(id):
            schedule(id: id).map { "your \($0.name) Schedule" } ?? "a Schedule"
        case let .budget(id):
            budget(id: id).map { "your \($0.name) Budget running out" } ?? "a Budget running out"
        }
    }
}

extension AppState {
    /// A label for a Lock on its own, such as "Manual Lock".
    public func title(for lock: Lock) -> String {
        switch lock.source {
        case .manual:
            "Manual Lock"
        case let .schedule(id):
            schedule(id: id)?.name ?? "Schedule"
        case let .budget(id):
            budget(id: id).map { "\($0.name) Budget" } ?? "Budget"
        }
    }
}
