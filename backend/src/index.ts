type ChallengePrompt =
  | "touch_grass"
  | "tree_or_hedge"
  | "outside_front_door"
  | "washing_machine"
  | "daylight_doorway";

type AttemptStatus = "created" | "uploaded" | "analyzing" | "passed" | "failed" | "expired";

type ChallengeResult = {
  passed: boolean;
  confidence: number;
  labels: string[];
  reason: string;
  redFlags: string[];
};

type ChallengeAttempt = {
  id: string;
  deviceId: string;
  sessionId: string;
  prompt: ChallengePrompt;
  status: AttemptStatus;
  imageObjectKey: string;
  result?: ChallengeResult;
  createdAt: string;
  expiresAt: string;
};

type Env = {
  CHALLENGE_IMAGES: R2Bucket;
  OPENAI_API_KEY?: string;
  OPENAI_MODEL?: string;
  TOUCHGRASS_API_TOKEN?: string;
  DEV_AUTO_PASS?: string;
  MAX_UPLOAD_BYTES?: string;
};

type CreateAttemptRequest = {
  deviceId?: string;
  sessionId?: string;
};

const PROMPTS: Record<ChallengePrompt, string> = {
  touch_grass: "Take a photo of your hand touching grass.",
  tree_or_hedge: "Take a photo of your hand near a tree or hedge.",
  outside_front_door: "Take a photo outside your front door.",
  washing_machine: "Take a photo of your washing machine from another room.",
  daylight_doorway: "Take a photo of daylight through an open doorway."
};

const ATTEMPT_TTL_MS = 10 * 60 * 1000;
const JSON_HEADERS = { "content-type": "application/json; charset=utf-8" };

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(request.url);

      if (request.method === "OPTIONS") {
        return cors(new Response(null, { status: 204 }));
      }

      if (url.pathname === "/health" && request.method === "GET") {
        return json({ ok: true });
      }

      const authError = authorize(request, env);
      if (authError) {
        return authError;
      }

      if (url.pathname === "/challenge-attempts" && request.method === "POST") {
        return createAttempt(request, env, url);
      }

      const match = url.pathname.match(/^\/challenge-attempts\/([^/]+)(?:\/([^/]+))?$/);
      if (!match) {
        return json({ error: "not_found" }, 404);
      }

      const [, attemptId, action] = match;

      if (!action && request.method === "GET") {
        return getAttempt(env, attemptId);
      }

      if (action === "image" && request.method === "PUT") {
        return uploadImage(request, env, attemptId);
      }

      if (action === "submit" && request.method === "POST") {
        return submitAttempt(env, attemptId);
      }

      return json({ error: "not_found" }, 404);
    } catch (error) {
      if (error instanceof HttpError) {
        return json({ error: error.code }, error.status);
      }

      return json(
        {
          error: "internal_error",
          message: error instanceof Error ? error.message : "Unknown error"
        },
        500
      );
    }
  }
};

async function createAttempt(request: Request, env: Env, url: URL): Promise<Response> {
  const body = (await readJson(request)) as CreateAttemptRequest;
  const sessionId = requiredString(body.sessionId, "sessionId");
  const deviceId = requiredString(body.deviceId, "deviceId");
  const id = crypto.randomUUID();
  const now = new Date();
  const prompt = pickPrompt(id);
  const imageObjectKey = `attempts/${id}/proof.jpg`;
  const attempt: ChallengeAttempt = {
    id,
    deviceId,
    sessionId,
    prompt,
    status: "created",
    imageObjectKey,
    createdAt: now.toISOString(),
    expiresAt: new Date(now.getTime() + ATTEMPT_TTL_MS).toISOString()
  };

  await saveAttempt(env, attempt);

  return json({
    attemptId: id,
    prompt,
    promptText: PROMPTS[prompt],
    uploadUrl: new URL(`/challenge-attempts/${id}/image`, url.origin).toString(),
    submitUrl: new URL(`/challenge-attempts/${id}/submit`, url.origin).toString(),
    expiresAt: attempt.expiresAt
  });
}

async function getAttempt(env: Env, attemptId: string): Promise<Response> {
  const attempt = await loadAttempt(env, attemptId);
  if (!attempt) {
    return json({ error: "not_found" }, 404);
  }

  return json(publicAttempt(attempt));
}

async function uploadImage(request: Request, env: Env, attemptId: string): Promise<Response> {
  const attempt = await activeAttempt(env, attemptId);
  const contentType = request.headers.get("content-type") ?? "application/octet-stream";

  if (!["image/jpeg", "image/jpg", "image/png", "image/webp"].includes(contentType.toLowerCase())) {
    return json({ error: "unsupported_media_type" }, 415);
  }

  const maxBytes = Number.parseInt(env.MAX_UPLOAD_BYTES ?? "5242880", 10);
  const contentLength = Number.parseInt(request.headers.get("content-length") ?? "0", 10);
  if (contentLength > maxBytes) {
    return json({ error: "payload_too_large", maxBytes }, 413);
  }

  if (!request.body) {
    return json({ error: "missing_body" }, 400);
  }

  await env.CHALLENGE_IMAGES.put(attempt.imageObjectKey, request.body, {
    httpMetadata: { contentType },
    customMetadata: {
      attemptId: attempt.id,
      sessionId: attempt.sessionId,
      deviceId: attempt.deviceId,
      prompt: attempt.prompt
    }
  });

  attempt.status = "uploaded";
  await saveAttempt(env, attempt);

  return json({ ok: true, attempt: publicAttempt(attempt) });
}

async function submitAttempt(env: Env, attemptId: string): Promise<Response> {
  const attempt = await activeAttempt(env, attemptId);
  const object = await env.CHALLENGE_IMAGES.get(attempt.imageObjectKey);

  if (!object) {
    return json({ error: "image_not_uploaded" }, 409);
  }

  attempt.status = "analyzing";
  await saveAttempt(env, attempt);

  const result = await validateImage(env, attempt, object);
  attempt.result = result;
  attempt.status = result.passed ? "passed" : "failed";
  await saveAttempt(env, attempt);

  return json({ attempt: publicAttempt(attempt) });
}

async function validateImage(
  env: Env,
  attempt: ChallengeAttempt,
  object: R2ObjectBody
): Promise<ChallengeResult> {
  if (!env.OPENAI_API_KEY) {
    if (env.DEV_AUTO_PASS === "true") {
      return {
        passed: true,
        confidence: 1,
        labels: ["dev_auto_pass"],
        reason: "DEV_AUTO_PASS is enabled and OPENAI_API_KEY is not configured.",
        redFlags: []
      };
    }

    return {
      passed: false,
      confidence: 0,
      labels: [],
      reason: "Vision validation is not configured.",
      redFlags: ["missing_openai_api_key"]
    };
  }

  const imageBytes = await object.arrayBuffer();
  const base64 = arrayBufferToBase64(imageBytes);
  const mimeType = object.httpMetadata?.contentType ?? "image/jpeg";
  const promptText = PROMPTS[attempt.prompt];
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
            {
              type: "input_text",
              text: validationPrompt(promptText)
            },
            {
              type: "input_image",
              image_url: `data:${mimeType};base64,${base64}`,
              detail: "low"
            }
          ]
        }
      ]
    })
  });

  if (!response.ok) {
    const message = await response.text();
    return {
      passed: false,
      confidence: 0,
      labels: [],
      reason: `Vision provider error: ${message.slice(0, 300)}`,
      redFlags: ["provider_error"]
    };
  }

  const data = await response.json();
  return normalizeVisionResult(extractOutputText(data));
}

function validationPrompt(promptText: string): string {
  return [
    "You are validating an anti-distraction unlock challenge photo.",
    "Return JSON only with keys: passed, confidence, labels, reason, redFlags.",
    "passed must be true only if the photo plausibly satisfies the prompt.",
    "Reject screenshots, photos of screens, blank images, memes, unrelated objects, or images too blurry to assess.",
    "confidence must be a number from 0 to 1.",
    `Challenge prompt: ${promptText}`
  ].join("\n");
}

function normalizeVisionResult(outputText: string): ChallengeResult {
  const parsed = parseJsonObject(outputText);
  const confidence = clampNumber(parsed.confidence, 0, 1);
  const labels = stringArray(parsed.labels);
  const redFlags = stringArray(parsed.redFlags);
  const reason = typeof parsed.reason === "string" ? parsed.reason.slice(0, 600) : "No reason provided.";
  const passed = parsed.passed === true && confidence >= 0.72 && redFlags.length === 0;

  return {
    passed,
    confidence,
    labels,
    reason,
    redFlags
  };
}

function extractOutputText(data: unknown): string {
  if (typeof data !== "object" || data === null) {
    return "";
  }

  const outputText = (data as { output_text?: unknown }).output_text;
  if (typeof outputText === "string") {
    return outputText;
  }

  const output = (data as { output?: unknown }).output;
  if (!Array.isArray(output)) {
    return "";
  }

  const parts: string[] = [];
  for (const item of output) {
    if (typeof item !== "object" || item === null) {
      continue;
    }

    const content = (item as { content?: unknown }).content;
    if (!Array.isArray(content)) {
      continue;
    }

    for (const contentItem of content) {
      if (typeof contentItem !== "object" || contentItem === null) {
        continue;
      }

      const text = (contentItem as { text?: unknown }).text;
      if (typeof text === "string") {
        parts.push(text);
      }
    }
  }

  return parts.join("\n").trim();
}

async function activeAttempt(env: Env, attemptId: string): Promise<ChallengeAttempt> {
  const attempt = await loadAttempt(env, attemptId);
  if (!attempt) {
    throw new HttpError(404, "not_found");
  }

  if (Date.parse(attempt.expiresAt) < Date.now()) {
    attempt.status = "expired";
    await saveAttempt(env, attempt);
    throw new HttpError(410, "attempt_expired");
  }

  return attempt;
}

async function loadAttempt(env: Env, attemptId: string): Promise<ChallengeAttempt | null> {
  const object = await env.CHALLENGE_IMAGES.get(attemptKey(attemptId));
  if (!object) {
    return null;
  }

  return (await object.json()) as ChallengeAttempt;
}

async function saveAttempt(env: Env, attempt: ChallengeAttempt): Promise<void> {
  await env.CHALLENGE_IMAGES.put(attemptKey(attempt.id), JSON.stringify(attempt, null, 2), {
    httpMetadata: { contentType: "application/json" }
  });
}

function publicAttempt(attempt: ChallengeAttempt) {
  return {
    id: attempt.id,
    sessionId: attempt.sessionId,
    prompt: attempt.prompt,
    promptText: PROMPTS[attempt.prompt],
    status: attempt.status,
    result: attempt.result,
    createdAt: attempt.createdAt,
    expiresAt: attempt.expiresAt
  };
}

function attemptKey(attemptId: string): string {
  return `attempts/${attemptId}/attempt.json`;
}

function pickPrompt(seed: string): ChallengePrompt {
  const prompts = Object.keys(PROMPTS) as ChallengePrompt[];
  const index = [...seed].reduce((acc, char) => acc + char.charCodeAt(0), 0) % prompts.length;
  return prompts[index];
}

async function readJson(request: Request): Promise<unknown> {
  try {
    return await request.json();
  } catch {
    throw new HttpError(400, "invalid_json");
  }
}

function requiredString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.trim().length === 0) {
    throw new HttpError(400, `missing_${field}`);
  }

  return value.trim();
}

function authorize(request: Request, env: Env): Response | null {
  if (!env.TOUCHGRASS_API_TOKEN) {
    return null;
  }

  const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const header = request.headers.get("x-touchgrass-api-token");

  if (bearer === env.TOUCHGRASS_API_TOKEN || header === env.TOUCHGRASS_API_TOKEN) {
    return null;
  }

  return json({ error: "unauthorized" }, 401);
}

function parseJsonObject(text: string): Record<string, unknown> {
  const trimmed = text.trim();
  const fenced = trimmed.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]?.trim();
  const candidate = fenced ?? trimmed.match(/\{[\s\S]*\}/)?.[0] ?? trimmed;

  try {
    const parsed = JSON.parse(candidate);
    return typeof parsed === "object" && parsed !== null ? (parsed as Record<string, unknown>) : {};
  } catch {
    return {
      passed: false,
      confidence: 0,
      labels: [],
      reason: "Vision model did not return parseable JSON.",
      redFlags: ["invalid_model_json"]
    };
  }
}

function stringArray(value: unknown): string[] {
  return Array.isArray(value)
    ? value.filter((item): item is string => typeof item === "string").map((item) => item.slice(0, 80))
    : [];
}

function clampNumber(value: unknown, min: number, max: number): number {
  if (typeof value !== "number" || Number.isNaN(value)) {
    return min;
  }

  return Math.min(Math.max(value, min), max);
}

function arrayBufferToBase64(buffer: ArrayBuffer): string {
  let binary = "";
  const bytes = new Uint8Array(buffer);
  const chunkSize = 0x8000;

  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    const chunk = bytes.subarray(offset, offset + chunkSize);
    binary += String.fromCharCode(...chunk);
  }

  return btoa(binary);
}

function json(body: unknown, status = 200): Response {
  return cors(
    new Response(JSON.stringify(body), {
      status,
      headers: JSON_HEADERS
    })
  );
}

function cors(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set("access-control-allow-origin", "*");
  headers.set("access-control-allow-methods", "GET,POST,PUT,OPTIONS");
  headers.set("access-control-allow-headers", "authorization,content-type,x-touchgrass-api-token");

  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers
  });
}

class HttpError extends Error {
  constructor(
    readonly status: number,
    readonly code: string
  ) {
    super(code);
  }
}
