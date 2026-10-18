import Foundation

/// A cross-process nudge that the shared state changed, so an open app can refresh when a control,
/// Shortcut or the monitor extension changes Locks behind its back.
public enum StateChangeSignal {
    static var name: CFString { "pear.TouchGrass.stateChanged" as CFString }

    public static func post() {
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(), CFNotificationName(name), nil, nil, true)
    }

    /// Calls `handler` on the main queue whenever any process posts the signal, for the life of the process.
    public static func observe(_ handler: @escaping @Sendable () -> Void) {
        let box = Unmanaged.passRetained(HandlerBox(handler)).toOpaque()
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(),
            box,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let handler = Unmanaged<HandlerBox>.fromOpaque(observer).takeUnretainedValue().handler
                DispatchQueue.main.async { handler() }
            },
            name,
            nil,
            .deliverImmediately
        )
    }

    private final class HandlerBox: Sendable {
        let handler: @Sendable () -> Void
        init(_ handler: @escaping @Sendable () -> Void) { self.handler = handler }
    }
}
