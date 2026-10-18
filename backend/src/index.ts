/**
 * The optional server Grass Check. The app POSTs a Touch Grass photo and gets back whether it shows
 * real grass. Photos are judged in memory and never stored.
 */

type GrassVerdict = {
  passed: boolean;
  confidence: number;
  labels: string[];
  reason: string;
};

type Env = {
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  TOUCHGRASS_API_TOKEN?: string;
  /** Local development only: accept requests without a token. */
  ALLOW_UNAUTHENTICATED?: string;
  DEV_AUTO_PASS?: string;
  MAX_UPLOAD_BYTES?: string;
};

const IMAGE_TYPES = ["image/jpeg", "image/jpg", "image/png", "image/webp"];
const PASS_CONFIDENCE = 0.72;
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (url.pathname === "/health" && request.method === "GET") {
      return json({ ok: true });
    }

    if (!isAuthorized(request, env)) {
      return json({ error: "unauthorized" }, 401);
    }

    if (url.pathname === "/grass-check" && request.method === "POST") {
      return checkGrass(request, env);
    }

    return json({ error: "not_found" }, 404);
  }
};

async function checkGrass(request: Request, env: Env): Promise<Response> {
  const contentType = (request.headers.get("content-type") ?? "").toLowerCase();
  if (!IMAGE_TYPES.includes(contentType)) {
    return json({ error: "unsupported_media_type" }, 415);
  }

  const maxBytes = Number.parseInt(env.MAX_UPLOAD_BYTES ?? "5242880", 10);
  const image = await request.arrayBuffer();
  if (image.byteLength === 0) {
    return json({ error: "missing_body" }, 400);
  }
  if (image.byteLength > maxBytes) {
    return json({ error: "payload_too_large", maxBytes }, 413);
  }

  return json(await judge(env, image, contentType));
}

async function judge(env: Env, image: ArrayBuffer, mimeType: string): Promise<GrassVerdict> {
  if (!env.OPENAI_API_KEY) {
    return env.DEV_AUTO_PASS === "true"
      ? { passed: true, confidence: 1, labels: ["dev_auto_pass"], reason: "DEV_AUTO_PASS is on and no OpenAI key is set." }
      : { passed: false, confidence: 0, labels: [], reason: "The server Grass Check isn't configured." };
  }

  const response = await fetch("https://api.openai.com/v1/responses", {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.OPENAI_API_KEY}`,
      "content-type": "application/json"
    },
    body: JSON.stringify({
      model: env.OPENAI_MODEL ?? "gpt-4.1-mini",
      input: [
        {
          role: "user",
          content: [
            { type: "input_text", text: PROMPT },
            { type: "input_image", image_url: `data:${mimeType};base64,${toBase64(image)}`, detail: "low" }
          ]
        }
      ]
    })
  });

  if (!response.ok) {
    return { passed: false, confidence: 0, labels: [], reason: `Vision provider error: ${(await response.text()).slice(0, 300)}` };
  }

  return normalise(parseJsonObject(extractOutputText(await response.json())));
}

const PROMPT = [
  "You are the referee for an app that only unlocks when the user photographs real, living grass outdoors.",
  "Return JSON only, with keys: passed (boolean), confidence (0 to 1), labels (short strings), reason (one sentence).",
  "passed is true only if real grass, such as a lawn, field or verge, fills a meaningful part of the photo.",
  "Other plants don't count: trees, hedges, moss, houseplants, flowers, crops that aren't grass.",
  "Reject artificial turf, photos of screens or prints, screenshots, blank or very blurry images."
].join("\n");

function normalise(parsed: Record<string, unknown>): GrassVerdict {
  const confidence = clamp(parsed.confidence);
  return {
    passed: parsed.passed === true && confidence >= PASS_CONFIDENCE,
    confidence,
    labels: Array.isArray(parsed.labels)
      ? parsed.labels.filter((label): label is string => typeof label === "string").map((label) => label.slice(0, 80))
      : [],
    reason: typeof parsed.reason === "string" ? parsed.reason.slice(0, 300) : "No reason given."
  };
}

function extractOutputText(data: unknown): string {
  if (typeof data !== "object" || data === null) return "";
  const outputText = (data as { output_text?: unknown }).output_text;
  if (typeof outputText === "string") return outputText;

  const output = (data as { output?: unknown }).output;
  if (!Array.isArray(output)) return "";
  return output
    .flatMap((item) => (Array.isArray(item?.content) ? item.content : []))
    .map((content: { text?: unknown }) => (typeof content?.text === "string" ? content.text : ""))
    .join("\n")
    .trim();
}

function parseJsonObject(text: string): Record<string, unknown> {
  const trimmed = text.trim();
  const candidate = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]?.trim() ?? trimmed.match(/\{[\s\S]*\}/)?.[0] ?? trimmed;
  try {
    const parsed = JSON.parse(candidate);
    return typeof parsed === "object" && parsed !== null ? parsed : {};
  } catch {
    return { passed: false, confidence: 0, reason: "The vision model didn't return readable JSON." };
  }
}

/** Without a token, every request is refused unless local development explicitly allows it,
 * so a deployed Worker can't spend OpenAI credit for strangers. */
function isAuthorized(request: Request, env: Env): boolean {
  if (!env.TOUCHGRASS_API_TOKEN) return env.ALLOW_UNAUTHENTICATED === "true";
  const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  return bearer === env.TOUCHGRASS_API_TOKEN;
}

function clamp(value: unknown): number {
  return typeof value === "number" && !Number.isNaN(value) ? Math.min(Math.max(value, 0), 1) : 0;
}

function toBase64(buffer: ArrayBuffer): string {
  let binary = "";
  const bytes = new Uint8Array(buffer);
  for (let offset = 0; offset < bytes.length; offset += 0x8000) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + 0x8000));
  }
  return btoa(binary);
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: JSON_HEADERS });
}
