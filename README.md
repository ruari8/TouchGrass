# Touch Grass

[![CI](https://github.com/ruari8/TouchGrass/actions/workflows/ci.yml/badge.svg)](https://github.com/ruari8/TouchGrass/actions/workflows/ci.yml)

Brick without the brick. Touch Grass locks your distracting apps, and the only normal way out is to go outside and take a photo of real grass.

You get Locked three ways:

- **Manual Lock** from the app, Control Center, the Lock Screen, the Action button or Shortcuts.
- **Schedules**, such as 10pm to 7am.
- **Budgets**, such as 1 hour of social media a day.

Each one locks a named Block List of apps. One Touch Grass covers every active Lock. For emergencies you hold up to 3 Emergency Unlocks, and each one you use comes back 30 days later.

The vocabulary used throughout the code and docs lives in [CONTEXT.md](CONTEXT.md).

## Repository layout

```text
ios/        iOS app and Screen Time extensions
package/    TouchGrassKit: domain logic (TouchGrassCore) and the Screen Time bridge (TouchGrassScreenTime)
backend/    Cloudflare Worker for the optional server Grass Check (debug and TestFlight builds only)
docs/       Architecture, the server Grass Check, and the ideas backlog
```

## Prerequisites

- Xcode 26 with the iOS 26 SDK.
- An Apple developer account with the Family Controls capability for real-device blocking. Blocking can't be tested in the simulator.
- Node.js 22, only for the optional Worker.

## Quick start

```sh
cd package && swift test
```

```sh
xcodebuild build \
  -project ios/TouchGrass.xcodeproj \
  -scheme TouchGrass \
  -destination 'platform=iOS Simulator,name=iPhone 17'
```

To run on a device, open `ios/TouchGrass.xcodeproj`. Then set your own signing team, bundle identifiers (`pear.TouchGrass*`) and App Group (`group.pear.TouchGrass`). Every target that touches the shields needs the Family Controls capability: the app, the monitor, both shield extensions and the controls extension.

Debug builds accept `-demo locked`, `-demo break` or `-demo unlocked` (and `-demoTab rules`) as launch arguments to skip setup with sample data.

## Needs testing on a real device

The simulator can't block apps, so these are untested:

- Shields applying and lifting, and Breaks re-locking on time. iOS delivers the background wake-up when it chooses.
- Budgets reaching their limit, including the guard against iOS 26 reporting a Budget as used up too early.
- Whether the Lock control applies shields without opening the app.
- Whether notifications from locked apps are silenced. Brick claims this; Touch Grass doesn't promise it.
