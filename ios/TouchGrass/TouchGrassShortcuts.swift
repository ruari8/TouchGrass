import AppIntents

/// Siri and Shortcuts phrases. Location triggers are Shortcuts automations that run `LockIntent`.
struct TouchGrassShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: LockIntent(),
            phrases: ["Lock my apps with \(.applicationName)", "Start a \(.applicationName) Lock"],
            shortTitle: "Lock",
            systemImageName: "lock.fill"
        )
        AppShortcut(
            intent: OpenTouchGrassIntent(),
            phrases: ["\(.applicationName)", "Unlock with \(.applicationName)"],
            shortTitle: "Touch Grass",
            systemImageName: "leaf.fill"
        )
    }
}
