# AI Coach

BlockOS uses OpenRouter for onboarding coaching recommendations.

## Current provider choice

- Provider: OpenRouter
- Model: `minimax/minimax-m2.7`
- Endpoint: `https://openrouter.ai/api/v1/chat/completions`
- Output mode: structured JSON via `response_format.type = json_schema`

This keeps the recommendation predictable enough for a mobile onboarding card instead of letting the model free-form ramble.

## Product intent

The coaching recommendation should feel like:

- calm
- direct
- practical
- strict enough to create friction
- not moralizing

It is meant to turn the user's onboarding answers into a realistic starting plan, not to act like therapy or a life coach.

## System prompt

The app currently instructs the model to:

- act as "BlockOS Coach"
- stay concise and non-judgmental
- recommend practical friction instead of dramatic abstinence by default
- avoid medical claims
- suggest only common consumer apps if naming apps
- return valid JSON only

## Inputs currently sent

- feeling
- stated behavior to reduce
- ideal daily screen-time target
- social-media allowance
- everything-else allowance

## Important current boundary

The onboarding screen already displays real Screen Time usage stats, but those stats are not yet injected into the AI prompt. Right now the AI recommendation is based on the user's onboarding answers, while the usage report remains a separate visual input on screen.

If we later want the model to reason over the usage summary directly, the clean next step is sharing the usage-report output with the main app through a shared container or moving recommendation generation server-side.

## Local setup

Configure the app with:

- `BLOCKOS_OPENROUTER_API_KEY`
- optional `BLOCKOS_OPENROUTER_APP_NAME`
- optional `BLOCKOS_OPENROUTER_SITE_URL`

For local development, the easiest path is setting these as Xcode scheme environment variables.

If no API key is configured, BlockOS falls back to the local heuristic recommendation so onboarding still works.
