# MVP Architecture

## Goal

Ship an iOS-only MVP that starts a focus session, applies app restrictions, and forces one of two unlock paths:

- Wait 120 seconds.
- Scan an app-generated QR code placed elsewhere.

The MVP is local-only and does not include accounts, sync, subscriptions, or advanced challenge validation.

## Layers

### Domain

Owns the session state machine, session models, unlock methods, override policy, and transition rules.

### Persistence

Stores block sets, session configuration, active session restoration state, QR token metadata, and unlock history.

### Enforcement

Wraps platform-specific app shielding and authorization behavior behind protocols so Apple framework details do not leak into core logic.

### App/UI

The iOS app target under ios will host onboarding, app selection, session start, active session, timer unlock, QR management, QR scan, history, and settings.

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

### Timer

- Fixed 120-second countdown.
- Must survive app lifecycle interruptions.
- Logs success, cancellation, timeout reset, and failure.

### QR

- Generated locally by the app.
- User can print, save, or share it elsewhere.
- Scan is validated locally against stored token metadata.

## Initial Repository Shape

- `ios/BlockOS.xcodeproj`: iOS application project.
- `ios/BlockOS`: iOS app target source files and assets.
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

## Implementation Order

1. Domain state machine.
2. Local persistence.
3. Enforcement interfaces.
4. App-facing coordinator.
5. iOS app target integration.
6. Timer unlock UI.
7. QR generation and scan UI.
