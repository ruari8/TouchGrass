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
  - Tightening edits apply at once, even while a loosening edit waits. When one edit does both, such as moving a Schedule from 22:00–07:00 to 21:00–06:00, a temporary copy of the new window runs alongside the old one until the edit applies.
  - Waiting edits apply at the first moment after their Reset Time when no Lock is active, so they never cut a running Lock short.
- `AppStateStore` saves the state as JSON in the App Group. Every change re-reads the file under a file coordinator, because the app and the extensions write to it from separate processes.

**TouchGrassScreenTime** (`package/Sources/TouchGrassScreenTime`) bridges to Apple's Screen Time frameworks.
- `Enforcement.applyShields` turns the state into shields on one named `ManagedSettingsStore`, while the state file is held. `scheduleBackgroundWork` runs after the file is released. It books a DeviceActivity wake-up for the next time the shields change on their own, such as a Break or a timed Lock ending, and syncs the Schedule and Budget activities. Stopping an activity can call back into the monitor, which would otherwise wait on the held file.
- `Enforcement.syncActivities` registers one repeating DeviceActivity per enabled Schedule. It leaves matching activities alone, because restarting one inside its window makes iOS call `intervalDidStart` again and would loop.
- A Block List's `FamilyActivitySelection` is stored inside it as encoded data that Core never opens. The Screen Time layer answers whether an edited list still covers the old one.
- Each enabled Budget gets a repeating DeviceActivity from Reset Time to Reset Time. Its one event fires when the Block List's apps reach the Budget's minutes.
  - Usage counts only from when monitoring began.
  - On iOS 26 the event sometimes fires within seconds of registering. Real usage can't add up faster than the clock, so a callback that arrives before the Budget's minutes have passed since counting began is ignored and the Budget is re-registered (see `shouldLockForBudgetThreshold`). This never Locks wrongly.
  - The trade-off is that editing a Budget mid-day restarts that day's count.
  - Reset Times are whole hours, because hourly usage segments can't represent anything finer.
  - This needs testing on a real device.
- The wake-up booking is left alone when unchanged, because stopping a running activity also calls `intervalDidEnd`. The monitor ignores a wake-up ending before its booked time.
- iOS allows 20 monitored activities per app. One is kept for wake-ups, which caps Schedules plus Budgets at 18.

**The app** (`ios/TouchGrass`) is SwiftUI.
- `AppModel` sends every change through the store and applies the shields while still holding the state file. The monitor extension does the same, so neither process can overwrite the other's shields with stale ones. A failed save is shown to the user and the saved state is reloaded.
- Rule changes are refused while any Lock is active.
- Emergency Unlock uses are mirrored to iCloud key-value storage, one key per use, so reinstalling the app doesn't refill them and two offline devices don't overwrite each other.

## Extensions

| Target | Job |
|---|---|
| TouchGrassMonitor | Woken by DeviceActivity when a Schedule window opens or closes, or when a wake-up ends. It reconciles Locks and re-syncs the shields. |
| TouchGrassShieldConfiguration | Draws the shield: "Locked.", which Block List the app is on, and what locked it. |
| TouchGrassShieldAction | Its "Touch Grass" button sends a notification that opens the camera, because a shield can't open the app directly. |
| TouchGrassUsageReport | Draws the Budget bars on Home from today's usage. This is the only place iOS reveals usage minutes, so the numbers never reach the app. |

## Grass Check

`GrassChecker` is a protocol. The default, `OnDeviceGrassChecker`, runs Apple's Vision image classifier and passes when its `grass` label scores at least 0.4. The camera is live-only. The simulator falls back to the photo library because it has no camera.

## Debugging

Debug builds accept `-demo locked`, `-demo break` or `-demo unlocked` as a launch argument. Each skips setup and loads sample data.
