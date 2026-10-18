import FamilyControls
import ManagedSettings
import ManagedSettingsUI
import TouchGrassCore
import TouchGrassScreenTime
import UIKit

/// The screen a Locked app shows instead of itself.
final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(name: application.localizedDisplayName) { list in
            application.token.map(list.contains) ?? false
        }
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(name: application.localizedDisplayName ?? category.localizedDisplayName) { list in
            (application.token.map(list.contains) ?? false) || (category.token.map(list.contains) ?? false)
        }
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(name: webDomain.domain) { list in
            webDomain.token.map(list.contains) ?? false
        }
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(name: webDomain.domain ?? category.localizedDisplayName) { list in
            (webDomain.token.map(list.contains) ?? false) || (category.token.map(list.contains) ?? false)
        }
    }

    private func makeConfiguration(name: String?, isOn: (BlockList) -> Bool) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundColor: ShieldPalette.background,
            icon: UIImage(systemName: "leaf.fill")?.withTintColor(ShieldPalette.grass, renderingMode: .alwaysOriginal),
            title: ShieldConfiguration.Label(text: "Locked.", color: .white),
            subtitle: ShieldConfiguration.Label(text: subtitle(name: name, isOn: isOn), color: ShieldPalette.subtitle),
            primaryButtonLabel: ShieldConfiguration.Label(text: "Touch Grass", color: ShieldPalette.background),
            primaryButtonBackgroundColor: ShieldPalette.grass,
            secondaryButtonLabel: ShieldConfiguration.Label(text: "Close", color: ShieldPalette.subtitle)
        )
    }

    private func subtitle(name: String?, isOn: (BlockList) -> Bool) -> String {
        let target = name ?? "This app"
        let state = (try? AppStateStore().load()) ?? AppState()
        let now = Date()
        let lock = state.locks.first { lock in
            lock.isEnforced(at: now) && state.blockList(id: lock.blockListID).map(isOn) == true
        }
        guard let lock, let list = state.blockList(id: lock.blockListID) else {
            return "\(target) is locked. Open Touch Grass and take a photo of real grass to unlock."
        }
        return "\(target) is on your \(list.name) Block List, locked by \(state.reason(for: lock)). Open Touch Grass and take a photo of real grass to unlock."
    }
}

private enum ShieldPalette {
    static let background = UIColor(red: 0.06, green: 0.11, blue: 0.08, alpha: 1)
    static let grass = UIColor(red: 0.45, green: 0.85, blue: 0.40, alpha: 1)
    static let subtitle = UIColor(white: 0.85, alpha: 1)
}
