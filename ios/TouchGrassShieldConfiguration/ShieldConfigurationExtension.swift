import ManagedSettings
import ManagedSettingsUI
import UIKit

final class ShieldConfigurationExtension: ShieldConfigurationDataSource {
    override func configuration(shielding application: Application) -> ShieldConfiguration {
        makeConfiguration(for: application.localizedDisplayName ?? "this app")
    }

    override func configuration(shielding application: Application, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(for: application.localizedDisplayName ?? category.localizedDisplayName ?? "this app")
    }

    override func configuration(shielding webDomain: WebDomain) -> ShieldConfiguration {
        makeConfiguration(for: webDomain.domain ?? "this site")
    }

    override func configuration(shielding webDomain: WebDomain, in category: ActivityCategory) -> ShieldConfiguration {
        makeConfiguration(for: webDomain.domain ?? category.localizedDisplayName ?? "this site")
    }

    private func makeConfiguration(for targetName: String) -> ShieldConfiguration {
        ShieldConfiguration(
            backgroundColor: ShieldPalette.background,
            icon: ShieldPalette.icon,
            title: ShieldConfiguration.Label(
                text: "Locked.",
                color: ShieldPalette.title
            ),
            subtitle: ShieldConfiguration.Label(
                text: "\(targetName) is locked. Go touch grass.",
                color: ShieldPalette.subtitle
            ),
            primaryButtonLabel: ShieldConfiguration.Label(
                text: "Close",
                color: ShieldPalette.buttonText
            ),
            primaryButtonBackgroundColor: ShieldPalette.buttonBackground
        )
    }
}

private enum ShieldPalette {
    static let background = UIColor(red: 0.16, green: 0.16, blue: 0.19, alpha: 1)
    static let title = UIColor.white
    static let subtitle = UIColor(red: 0.87, green: 0.87, blue: 0.90, alpha: 1)
    static let buttonText = UIColor.white
    static let buttonBackground = UIColor(red: 0.36, green: 0.40, blue: 0.48, alpha: 1)
    static let icon = UIImage(systemName: "lock.shield.fill")
}
