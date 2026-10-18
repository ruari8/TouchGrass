# Architecture

Touch Grass is an iOS 26 app plus four Screen Time extensions, built on a local Swift package. The vocabulary is in [CONTEXT.md](../CONTEXT.md).

## Layers

**TouchGrassCore** (`package/Sources/TouchGrassCore`) is plain Swift, so its tests run on macOS.
- `AppState` holds everything the app remembers.
- The `LockEngine` extension holds the rules for getting Locked and getting out: Manual and automatic Locks, Touch Grass, Breaks and Emergency Unlocks.
- `reconcile(at:)` brings Locks in line with the clock. It applies waiting rule changes, forgets ended Locks, and starts a Lock for every Schedule whose window is open. It is safe to call repeatedly, and both the app and the monitor extension call it whenever they wake.
- `changeRules` is the only way to edit Block Lists, Schedules and Settings.
  - Edits are refused while Locked.
  - Loosening edits wait until the next Reset Time when "Loosening waits until tomorrow" is on (the Strict default). Examples: deleting a Schedule, shrinking its window, removing apps from a list, or switching to Flexible.
  - Tightening edits apply at once.
- `AppStateStore` saves the state as JSON in the App Group. Every change re-reads the file under a file coordinator, because the app and the extensions write to it from separate processes.

**TouchGrassScreenTime** (`package/Sources/TouchGrassScreenTime`) bridges to Apple's Screen Time frameworks.
- `Enforcement.sync` turns the state into shields on one named `ManagedSettingsStore`. It also books a DeviceActivity wake-up for the next time the shields change on their own, such as a Break or a timed Lock ending.
- `Enforcement.syncActivities` registers one repeating DeviceActivity per enabled Schedule. It leaves matching activities alone, because restarting one inside its window makes iOS call `intervalDidStart` again and would loop.
- A Block List's `FamilyActivitySelection` is stored inside it as encoded data that Core never opens. The Screen Time layer answers whether an edited list still covers the old one.
- iOS allows 20 monitored activities per app. One is kept for wake-ups, which caps Schedules plus Budgets at 18.

**The app** (`ios/TouchGrass`) is SwiftUI.
- `AppModel` sends every change through the store and then re-syncs the shields.
- Rule changes are refused while any Lock is active.
- Emergency Unlock uses are mirrored to iCloud key-value storage, so reinstalling the app doesn't refill them.

## Extensions

| Target | Job |
|---|---|
| TouchGrassMonitor | Woken by DeviceActivity when a Schedule window opens or closes, or when a wake-up ends. It reconciles Locks and re-syncs the shields. |
| TouchGrassShieldConfiguration | Draws the shield: "Locked.", which Block List the app is on, and what locked it. |
| TouchGrassShieldAction | Its "Touch Grass" button sends a notification that opens the camera, because a shield can't open the app directly. |
| TouchGrassUsageReport | DeviceActivityReport views. This is the only place iOS reveals usage minutes. |

## Grass Check

`GrassChecker` is a protocol. The default, `OnDeviceGrassChecker`, runs Apple's Vision image classifier and passes when its `grass` label scores at least 0.4. The camera is live-only. The simulator falls back to the photo library because it has no camera.

## Debugging

Debug builds accept `-demo locked`, `-demo break` or `-demo unlocked` as a launch argument. Each skips setup and loads sample data.
