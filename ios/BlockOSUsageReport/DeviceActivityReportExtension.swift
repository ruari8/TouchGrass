import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct BlockOSUsageReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        OnboardingUsageReport { summary in
            OnboardingUsageSummaryView(summary: summary)
        }
    }
}
