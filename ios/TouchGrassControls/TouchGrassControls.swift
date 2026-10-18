import AppIntents
import SwiftUI
import WidgetKit

@main
struct TouchGrassControls: WidgetBundle {
    var body: some Widget {
        LockControl()
        TouchGrassControl()
    }
}

/// Locks the default Block List from Control Center, the Lock Screen or the Action button.
struct LockControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "pear.TouchGrass.lock") {
            ControlWidgetButton(action: LockIntent()) {
                Label("Lock", systemImage: "lock.fill")
            }
        }
        .displayName("Lock")
        .description("Lock your default Block List until you touch grass.")
    }
}

/// Opens the Touch Grass camera.
struct TouchGrassControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "pear.TouchGrass.touchGrass") {
            ControlWidgetButton(action: OpenTouchGrassIntent()) {
                Label("Touch Grass", systemImage: "leaf.fill")
            }
        }
        .displayName("Touch Grass")
        .description("Open the camera to unlock.")
    }
}
