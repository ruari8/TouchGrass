# Challenge Validation

The Touch Grass MVP can run in two modes:

- Local friction only: the app unlocks after camera capture, with no backend configured.
- Verified challenge mode: the app uploads the captured photo to a Cloudflare Worker, stores it in R2, asks a vision model whether the photo satisfies the prompt, and unlocks only when the response passes.

## Backend

The Worker lives in `backend/` and exposes:

- `GET /health`
- `POST /challenge-attempts`
- `PUT /challenge-attempts/:id/image`
- `POST /challenge-attempts/:id/submit`
- `GET /challenge-attempts/:id`

Images and attempt metadata are stored in the `CHALLENGE_IMAGES` R2 bucket. The Worker accepts an optional bearer token through `TOUCHGRASS_API_TOKEN`; use it for any non-local deployment.

## Local Setup

```sh
cd backend
npm install
cp .dev.vars.example .dev.vars
```

For a local smoke test without OpenAI, set `DEV_AUTO_PASS=true` in `.dev.vars` and run:

```sh
npm run dev
```

Do not use `DEV_AUTO_PASS=true` in production.

## Cloudflare Setup

```sh
cd backend
npx wrangler login
npx wrangler r2 bucket create touchgrass-challenge-images
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put TOUCHGRASS_API_TOKEN
npm run deploy
```

Generate `TOUCHGRASS_API_TOKEN` with a password manager or:

```sh
openssl rand -base64 32
```

The deployed Worker URL becomes the app's `TOUCHGRASS_CHALLENGE_API_BASE_URL`.

## iOS Configuration

Set these build settings for the `TouchGrass` app target:

- `TOUCHGRASS_CHALLENGE_API_BASE_URL=https://<your-worker>.<your-account>.workers.dev`
- `TOUCHGRASS_CHALLENGE_API_TOKEN=<same token used for TOUCHGRASS_API_TOKEN>`

The generated Info.plist forwards both values into the app. Empty or unresolved `$(...)` values are ignored, so local builds without backend configuration keep using the friction-only path.

For ad-hoc simulator/device testing, the same keys can be set through `UserDefaults` before launching the unlock flow:

```swift
UserDefaults.standard.set("https://<worker-url>", forKey: "TOUCHGRASS_CHALLENGE_API_BASE_URL")
UserDefaults.standard.set("<token>", forKey: "TOUCHGRASS_CHALLENGE_API_TOKEN")
```

Never commit real API keys, Worker tokens, or `.dev.vars`.

## Validation Policy

The model is prompted to return JSON with:

- `passed`
- `confidence`
- `labels`
- `reason`
- `redFlags`

The Worker only accepts results where `passed` is true, `confidence >= 0.72`, and there are no red flags. This is not high-assurance identity or liveness proof yet, but it closes the biggest MVP loophole: any random camera image no longer unlocks the phone.
