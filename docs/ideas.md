# Ideas Backlog

This document keeps future ideas from getting lost while the MVP stays small.

## Decided

The design agreed for Touch Grass lives in [CONTEXT.md](../CONTEXT.md) and [architecture.md](architecture.md). Two ideas from the old app were dropped on purpose:
- The timer unlock fallback. Emergency Unlocks are the only way out besides touching grass.
- Unlock challenges other than grass. Touch Grass is grass only.

Everything below is a backlog of ideas, not plans.

## Physical Challenge Ideas

- Stand up and walk for a required duration.
- Walk to a saved location in the house.
- Tap a paired physical token or NFC sticker.
- Push-up or sit-up count verified by motion heuristics.

## Mental Challenge Ideas

- Short puzzle before unlocking.
- Memory pattern challenge.
- Arithmetic streak with escalating difficulty.
- Typed reflection prompt before access is restored.

## Activity and Photo Ideas

- Take a photo of a real-world object category.
- Take a live selfie in a different room.
- Capture a hand-on-object proof photo.
- Take a picture outdoors with liveness checks.
- Rotate prompts daily so users cannot pre-stage the same proof every time.

## Motion and Location Ideas

- Step-count threshold.
- Distance walked from session start.
- GPS radius challenge.
- Climb stairs before unlock.

## Social and Accountability Ideas

- Friend-approved override.
- Shared focus room.
- Daily accountability digest.
- Team or family challenge rules.

## Anti-Cheat Ideas

- Cooldown after failed unlock attempts.
- Longer timer after emergency override.
- Session edits disabled while active.
- Delayed exit after changing rules.
- History flag for aborted or forced exits.
- Distinguish normal unlock vs override unlock in analytics.
- Image classification for the chosen prompt.
- Camera liveness checks and stale-photo prevention.

## Product Notes

- Keep the product framed as intentional friction, not impossible lockout.
- Physical separation is stronger than on-device friction, so the software moat should come from good challenge design and clean UX.
- Promote new challenge types only after session restoration and shielding are stable.
- Supervised / MDM device management was considered and explicitly rejected for the app version. It would unlock features like device-wide restrictions, hidden apps, enforced home-screen policy, and Single App Mode, but that is a different managed-device product, not a normal downloadable Touch Grass app.
- The app version stays inside Family Controls / Screen Time constraints, so product differentiation has to come from challenge design, coaching, reporting, and shield UX rather than deeper operating-system control.
