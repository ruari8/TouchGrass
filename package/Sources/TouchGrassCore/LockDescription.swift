import Foundation

extension AppState {
    /// A short phrase naming what started a Lock, such as "a Manual Lock".
    public func reason(for lock: Lock) -> String {
        switch lock.source {
        case .manual:
            "a Manual Lock"
        case .schedule:
            "a Schedule"
        case .budget:
            "a Budget running out"
        }
    }
}

extension AppState {
    /// A label for a Lock on its own, such as "Manual Lock".
    public func title(for lock: Lock) -> String {
        switch lock.source {
        case .manual:
            "Manual Lock"
        case .schedule:
            "Schedule"
        case .budget:
            "Budget"
        }
    }
}
