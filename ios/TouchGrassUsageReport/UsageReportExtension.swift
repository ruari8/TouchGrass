import DeviceActivity
import ExtensionKit
import SwiftUI

@main
struct TouchGrassUsageReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        TotalUsageReport { minutes in
            Text("\(minutes) min")
        }
    }
}

struct TotalUsageReport: DeviceActivityReportScene {
    let context = DeviceActivityReport.Context("total")
    let content: (Int) -> Text

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> Int {
        var total: TimeInterval = 0
        for await activity in data {
            for await segment in activity.activitySegments {
                total += segment.totalActivityDuration
            }
        }
        return Int(total / 60)
    }
}
