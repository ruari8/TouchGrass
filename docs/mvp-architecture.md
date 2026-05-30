# MVP Architecture

## Goal

Ship an iOS-only MVP that turns selected apps/categories into a software Brick:

- The user grants Screen Time / Family Controls access.
- The user sets a daily selected-use limit, for example 1 hour of social media.
- When selected usage reaches the limit, iOS shields those apps/categories.
- To unblock, the user completes a real-world "Touch Grass" photo challenge.

The MVP is local-only and does not include accounts, sync, subscriptions, or advanced challenge validation.

## Layers

### Domain

Owns the session state machine, session models, unlock methods, override policy, and transition rules.

### Persistence

Stores block sets, onboarding configuration, active session restoration state, daily limit lock state, QR token metadata, and unlock history.

### Enforcement

Wraps platform-specific app shielding, authorization behavior, and Device Activity threshold monitoring so Apple framework details do not leak into core logic.

### App/UI

The iOS app target under ios hosts onboarding, app/category selection, daily budget setup, active lock state, Touch Grass challenge unlock, timer fallback, history, and settings.

## Core Session States

- `idle`
- `arming`
- `activeBlocked`
- `unlockChallengeInProgress`
- `unlockPending`
- `unlockedGrace`
- `completed`
- `abortedEmergencyOverride`

## MVP Unlock Methods

### Touch Grass Photo

- Default unlock path.
- Prompts the user to photograph a real-world object or place, such as grass, a hedge/tree, the outside of the front door, or a washing machine.
- Uses camera capture as proof-of-action friction. The MVP does not perform image classification or liveness verification.

### Timer Fallback

- Fixed 120-second countdown.
- Available as a backup when the camera is unavailable.
- Logs success, cancellation, timeout reset, and failure.

## Daily Limit Enforcement

- Onboarding saves the daily target and selected Screen Time targets into the shared App Group.
- The app starts a repeating `DeviceActivityCenter` monitor for the selected apps/categories/websites.
- The monitor uses `includesPastActivity` so the threshold reflects same-day usage, not only usage after the app was opened.
- The `BlockOSDailyLimitMonitor` extension applies a named `ManagedSettingsStore` shield when the threshold fires.
- When the user completes the unlock challenge, the app clears both the app session shield and the named daily-limit shield for the day.

## Initial Repository Shape

- `ios/BlockOS.xcodeproj`: iOS application project.
- `ios/BlockOS`: iOS app target source files and assets.
- `ios/BlockOSDailyLimitMonitor`: Device Activity monitor extension that applies shields when the daily limit is reached.
- `package/Package.swift`: local Swift package manifest.
- `package/Sources/BlockOSDomain`: session engine and models.
- `package/Sources/BlockOSPersistence`: local session and QR storage.
- `package/Sources/BlockOSEnforcement`: shielding abstractions and no-op development implementation.
- `package/Sources/BlockOSAppSupport`: app-facing coordinator layer.
- `package/Tests/BlockOSDomainTests`: package tests.
- `docs/ideas.md`: backlog of future challenge ideas.
- `docs/mvp-architecture.md`: architecture note.

## Biggest Risks

1. Apple entitlement approval for Family Controls.
2. Reliable lifecycle restoration of an active session.
3. Correct cleanup so shielding is always removed when a session finishes.
4. Avoiding accidental bypass through poorly defined state transitions.
5. Challenge validation is intentionally soft until camera, liveness, and classification behavior is designed.

## Implementation Order

1. Domain state machine.
2. Local persistence and App Group storage.
3. Enforcement interfaces.
4. Device Activity threshold monitoring.
5. App-facing coordinator.
6. iOS app target integration.
7. Touch Grass photo challenge UI.
8. Timer fallback UI.
