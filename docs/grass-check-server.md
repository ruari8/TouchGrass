# Server Grass Check

An optional second referee for Touch Grass photos, for comparing against Apple's on-device check. It's a Cloudflare Worker in `backend/` that sends the photo to an OpenAI vision model and returns whether it shows real grass. Photos are judged in memory and never stored.

Only debug and TestFlight builds can use it, by choosing **Server (OpenAI)** in Rules → Settings → Developer Settings. App Store builds always use the on-device check.

## API

- `GET /health` returns `{ "ok": true }`.
- `POST /grass-check` takes the JPEG, PNG or WebP photo as the request body, with a matching `Content-Type`. It returns:

```json
{ "passed": true, "confidence": 0.91, "labels": ["lawn", "grass"], "reason": "A mown lawn fills the frame." }
```

`passed` is only true when the model says yes with a confidence of at least 0.72. Trees, moss, houseplants, artificial turf and photos of screens are rejected.

Requests need `Authorization: Bearer <token>` matching `TOUCHGRASS_API_TOKEN`. Without a token set, the Worker refuses every request, unless `ALLOW_UNAUTHENTICATED=true` is set for local development.

## Run it locally

```sh
cd backend
npm install
cp .dev.vars.example .dev.vars   # then fill in OPENAI_API_KEY
npm run dev
```

To smoke-test without OpenAI, leave `OPENAI_API_KEY` empty and set `DEV_AUTO_PASS=true` in `.dev.vars`. Every photo then passes. Never deploy with that setting.

## Deploy

```sh
cd backend
npx wrangler secret put OPENAI_API_KEY
npx wrangler secret put TOUCHGRASS_API_TOKEN   # a long random string, e.g. from `openssl rand -hex 32`
npm run deploy
```

Then put the deployed URL and the token into Developer Settings on the phone.
