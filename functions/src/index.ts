import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {createHash} from "crypto";
import * as path from "path";
import * as fs from "fs";
import { processAIRequest } from "./aiRequest";

admin.initializeApp();

const db = admin.firestore();

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Lowercase + trim an email address. */
function normalizeEmail(email: string): string {
  return email.trim().toLowerCase();
}

/** SHA-256 hex hash of a string. */
function sha256(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

/** Generate a random 4-digit code (1000–9999). */
function generateCode(): string {
  const code = Math.floor(1000 + Math.random() * 9000);
  return code.toString();
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const CODES_COLLECTION = "email_codes";
const CODE_EXPIRY_MINUTES = 10;
const MAX_REQUESTS_PER_HOUR = 5;
const MAX_VERIFY_ATTEMPTS = 5;
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour

// ---------------------------------------------------------------------------
// 1. requestEmailCode
// ---------------------------------------------------------------------------

export const requestEmailCode = functions.runWith({
  secrets: ["ONESIGNAL_APP_ID", "ONESIGNAL_REST_API_KEY"],
}).https.onCall(
  async (data, context) => {
    const rawEmail: string | undefined = data?.email;
    if (!rawEmail || typeof rawEmail !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid email address is required."
      );
    }

    const email = normalizeEmail(rawEmail);
    const emailHash = sha256(email);
    const docRef = db.collection(CODES_COLLECTION).doc(emailHash);
    const now = Date.now();

    // --- Rate limiting ---
    const existing = await docRef.get();
    if (existing.exists) {
      const d = existing.data()!;
      const windowStart: number = d.windowStart ?? 0;
      const requestCount: number = d.requestCount ?? 0;

      if (now - windowStart < RATE_LIMIT_WINDOW_MS) {
        if (requestCount >= MAX_REQUESTS_PER_HOUR) {
          throw new functions.https.HttpsError(
            "resource-exhausted",
            "Too many code requests. Please try again later."
          );
        }
      }
    }

    // --- Generate and store code ---
    const code = generateCode();
    const codeHash = sha256(code);
    const expiresAt = now + CODE_EXPIRY_MINUTES * 60 * 1000;

    // Determine rate-limit window values
    let windowStart = now;
    let requestCount = 1;
    if (existing.exists) {
      const d = existing.data()!;
      const prevWindowStart: number = d.windowStart ?? 0;
      if (now - prevWindowStart < RATE_LIMIT_WINDOW_MS) {
        windowStart = prevWindowStart;
        requestCount = (d.requestCount ?? 0) + 1;
      }
    }

    await docRef.set({
      codeHash,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt,
      attempts: 0,
      used: false,
      windowStart,
      requestCount,
    });

    // --- Send email via OneSignal REST API ---
    const appId = (process.env.ONESIGNAL_APP_ID ?? "").trim();
    const apiKey = (process.env.ONESIGNAL_REST_API_KEY ?? "").trim();

    if (!appId || !apiKey) {
      functions.logger.error(
        "OneSignal secrets not configured. " +
          "ONESIGNAL_APP_ID present: " + !!appId +
          ", ONESIGNAL_REST_API_KEY present: " + !!apiKey
      );
      throw new functions.https.HttpsError(
        "internal",
        "Email service is not configured."
      );
    }

    functions.logger.info(
      `EMAIL_AUTH: [SEND] Preparing email for ${email}, appId=${appId.substring(0, 8)}...`
    );

    // On-brand colors from Auth flow: backgroundDarkPurple, dojoTurquoise, foregroundLightGray, textForegroundGray, inputFieldBackground
    const emailBody = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta http-equiv="Content-Type" content="text/html; charset=UTF-8">
  <title>Your Dojo verification code</title>
  <style type="text/css">
    @import url('https://fonts.googleapis.com/css2?family=Nunito:wght@400;600;700&display=swap');
  </style>
</head>
<body style="margin:0;padding:0;background-color:#2E2E4C;font-family:'Nunito',Arial,sans-serif;-webkit-text-size-adjust:100%;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="background-color:#2E2E4C;padding:32px 16px;">
    <tr>
      <td align="center" style="padding:0;">
        <table role="presentation" width="100%" cellpadding="0" cellspacing="0" border="0" style="max-width:400px;background-color:#454565;border-radius:16px;padding:40px 32px;">
          <tr>
            <td align="center" style="padding-bottom:28px;">
              <span style="color:#E2E2E2;font-size:28px;font-weight:700;font-family:'Nunito',Arial,sans-serif;margin:0;">Dojo</span>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-bottom:12px;">
              <p style="color:#C9C9C9;font-size:16px;font-weight:400;font-family:'Nunito',Arial,sans-serif;margin:0;line-height:1.4;">Your verification code:</p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <p style="color:#03DAC5;font-size:36px;font-weight:700;font-family:'Nunito',Arial,sans-serif;letter-spacing:10px;margin:0;">${code}</p>
            </td>
          </tr>
          <tr>
            <td align="center" style="padding-bottom:24px;">
              <p style="color:#C9C9C9;font-size:14px;font-weight:400;font-family:'Nunito',Arial,sans-serif;margin:0;line-height:1.5;">Expires in ${CODE_EXPIRY_MINUTES} minutes.</p>
            </td>
          </tr>
          <tr>
            <td align="center">
              <p style="color:#8a8a9a;font-size:12px;font-weight:400;font-family:'Nunito',Arial,sans-serif;margin:0;">If you didn't request this, you can safely ignore it.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
    <tr>
      <td align="center" style="padding-top:24px;">
        <span style="color:#2E2E4C;font-size:1px;">@medidojo.com #${code}</span>
      </td>
    </tr>
  </table>
</body>
</html>`.trim();

    const onesignalHeaders = {
      "Authorization": `Basic ${apiKey}`,
      "Content-Type": "application/json",
    };

    try {
      // Step 1: Ensure the email is registered as a OneSignal user.
      // Create/update a user with this email so we can send to them.
      // Uses the OneSignal User API to create a subscription.
      functions.logger.info(
        `EMAIL_AUTH: [SEND] Step 1 - Ensuring email ${email} exists in OneSignal`
      );

      const userPayload = {
        properties: {},
        subscriptions: [
          {
            type: "Email",
            token: email,
            enabled: true,
          },
        ],
      };

      const userResponse = await fetch(
        `https://api.onesignal.com/apps/${appId}/users`,
        {
          method: "POST",
          headers: onesignalHeaders,
          body: JSON.stringify(userPayload),
        }
      );

      // 200/201 = created, 409 = already exists — all fine
      if (!userResponse.ok && userResponse.status !== 409) {
        const userBody = await userResponse.text();
        functions.logger.warn(
          `EMAIL_AUTH: [SEND] OneSignal user create returned ${userResponse.status}: ${userBody} (continuing anyway)`
        );
      } else {
        functions.logger.info(
          `EMAIL_AUTH: [SEND] OneSignal user ensured (status: ${userResponse.status})`
        );
      }

      // Step 2: Send the verification email
      functions.logger.info(
        `EMAIL_AUTH: [SEND] Step 2 - Sending verification email to ${email}`
      );

      const response = await fetch("https://api.onesignal.com/notifications", {
        method: "POST",
        headers: onesignalHeaders,
        body: JSON.stringify({
          app_id: appId,
          include_email_tokens: [email],
          email_subject: `Your Dojo code: ${code}`,
          email_body: emailBody,
          email_from_name: "Dojo",
          email_from_address: "hello@medidojo.com",
        }),
      });

      const responseBody = await response.text();

      if (!response.ok) {
        functions.logger.error(
          `EMAIL_AUTH: [SEND] OneSignal notification FAILED (${response.status}): ${responseBody}`
        );
        throw new functions.https.HttpsError(
          "internal",
          "Failed to send verification email. Please try again."
        );
      }

      functions.logger.info(
        `EMAIL_AUTH: [SEND] Verification email sent to ${email} (hash: ${emailHash}), response: ${responseBody}`
      );
    } catch (err: unknown) {
      if (err instanceof functions.https.HttpsError) throw err;
      const errMsg = err instanceof Error ? err.message : String(err);
      functions.logger.error(
        `EMAIL_AUTH: [SEND] Unexpected error: ${errMsg}`
      );
      throw new functions.https.HttpsError(
        "internal",
        "Failed to send verification email. Please try again."
      );
    }

    return {success: true};
  }
);

// ---------------------------------------------------------------------------
// 2. verifyEmailCode
// ---------------------------------------------------------------------------

export const verifyEmailCode = functions.https.onCall(
  async (data, _context) => {
    const rawEmail: string | undefined = data?.email;
    const rawCode: string | undefined = data?.code;

    if (!rawEmail || typeof rawEmail !== "string") {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid email address is required."
      );
    }
    if (!rawCode || typeof rawCode !== "string" || rawCode.length !== 4) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "A valid 4-digit code is required."
      );
    }

    const email = normalizeEmail(rawEmail);
    const emailHash = sha256(email);
    const docRef = db.collection(CODES_COLLECTION).doc(emailHash);

    const doc = await docRef.get();
    if (!doc.exists) {
      throw new functions.https.HttpsError(
        "not-found",
        "No verification code found. Please request a new code."
      );
    }

    const d = doc.data()!;
    const now = Date.now();

    // Check expiry
    if (now > d.expiresAt) {
      throw new functions.https.HttpsError(
        "deadline-exceeded",
        "This code has expired. Please request a new code."
      );
    }

    // Check if already used
    if (d.used === true) {
      throw new functions.https.HttpsError(
        "already-exists",
        "This code has already been used. Please request a new code."
      );
    }

    // Check attempt limit
    if ((d.attempts ?? 0) >= MAX_VERIFY_ATTEMPTS) {
      throw new functions.https.HttpsError(
        "resource-exhausted",
        "Too many incorrect attempts. Please request a new code."
      );
    }

    // Increment attempts atomically
    await docRef.update({
      attempts: admin.firestore.FieldValue.increment(1),
    });

    // Validate code
    const submittedHash = sha256(rawCode);
    if (submittedHash !== d.codeHash) {
      const remaining = MAX_VERIFY_ATTEMPTS - ((d.attempts ?? 0) + 1);
      return {
        success: false,
        error: "Invalid code",
        remainingAttempts: remaining,
      };
    }

    // Code is valid — mark as used
    await docRef.update({used: true});

    // --- Get or create Firebase Auth user ---
    let uid: string;
    let isNewUser = false;

    try {
      const existingUser = await admin.auth().getUserByEmail(email);
      uid = existingUser.uid;
      functions.logger.info(
        `Existing user found for ${email}: ${uid}`
      );
    } catch (err: unknown) {
      // User does not exist — create one
      if (
        typeof err === "object" &&
        err !== null &&
        "code" in err &&
        (err as {code: string}).code === "auth/user-not-found"
      ) {
        const newUser = await admin.auth().createUser({email});
        uid = newUser.uid;
        isNewUser = true;
        functions.logger.info(
          `New user created for ${email}: ${uid}`
        );
      } else {
        functions.logger.error("Error looking up user:", err);
        throw new functions.https.HttpsError(
          "internal",
          "Failed to process authentication."
        );
      }
    }

    // Generate Firebase Custom Token
    const customToken = await admin.auth().createCustomToken(uid);

    return {
      success: true,
      customToken,
      isNewUser,
    };
  }
);

// ---------------------------------------------------------------------------
// 3. cleanupExpiredCodes (scheduled — every 60 minutes)
// ---------------------------------------------------------------------------

export const cleanupExpiredCodes = functions.pubsub
  .schedule("every 60 minutes")
  .onRun(async (_context) => {
    const now = Date.now();
    const snapshot = await db
      .collection(CODES_COLLECTION)
      .where("expiresAt", "<", now)
      .get();

    if (snapshot.empty) {
      functions.logger.info("No expired codes to clean up.");
      return null;
    }

    const batch = db.batch();
    snapshot.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();

    functions.logger.info(
      `Cleaned up ${snapshot.size} expired verification codes.`
    );
    return null;
  });

// ---------------------------------------------------------------------------
// 4. proxyOpenAIChat — OpenAI API proxy (keeps API key server-side)
// ---------------------------------------------------------------------------

interface ProxyOpenAIRequest {
  model: string;
  messages: Array<{ role: string; content: string }>;
  max_tokens: number;
  temperature: number;
}

export const proxyOpenAIChat = functions.runWith({
  secrets: ["OPENAI_API_KEY"],
}).https.onCall(
  async (data: unknown, context) => {
    const apiKey = (process.env.OPENAI_API_KEY ?? "").trim();
    if (!apiKey) {
      functions.logger.error("OPENAI_PROXY: OPENAI_API_KEY secret not configured");
      throw new functions.https.HttpsError(
        "internal",
        "AI service is not configured."
      );
    }

    const body = data as ProxyOpenAIRequest;
    if (!body?.model || !Array.isArray(body?.messages)) {
      throw new functions.https.HttpsError(
        "invalid-argument",
        "Invalid request: model and messages required."
      );
    }

    const payload = {
      model: body.model || "gpt-4o-mini",
      messages: body.messages,
      max_tokens: body.max_tokens ?? 300,
      temperature: body.temperature ?? 0.7,
    };

    try {
      const response = await fetch("https://api.openai.com/v1/chat/completions", {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${apiKey}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(payload),
      });

      const responseBody = await response.text();

      if (!response.ok) {
        functions.logger.error(
          `OPENAI_PROXY: OpenAI API error (${response.status}): ${responseBody}`
        );
        throw new functions.https.HttpsError(
          "internal",
          "AI service temporarily unavailable."
        );
      }

      const parsed = JSON.parse(responseBody);
      return parsed;
    } catch (err: unknown) {
      if (err instanceof functions.https.HttpsError) throw err;
      const errMsg = err instanceof Error ? err.message : String(err);
      functions.logger.error(`OPENAI_PROXY: Unexpected error: ${errMsg}`);
      throw new functions.https.HttpsError(
        "internal",
        "AI service temporarily unavailable."
      );
    }
  }
);

// ---------------------------------------------------------------------------
// 5. getCatalogs — HTTP GET endpoint for aggregated meditation catalogs
// ---------------------------------------------------------------------------

const CONTENT_STORAGE_BUCKET = "imagine-c6162.appspot.com";
const CATALOG_FILE_NAMES = [
  "background_music",
  "binaural_beats",
  "cues",
  "introduction",
  "body_scan",
  "perfect_breath",
  "i_am_mantra",
  "nostril_focus",
] as const;

interface RepoCatalogModel {
  id: string;
  name: string;
  path: string;
  voices?: Record<string, string>;
  duration_minutes?: number;
  description?: string;
}

interface RepoCatalogFile {
  version?: string;
  models: RepoCatalogModel[];
}

interface VoiceItem {
  id: string;
  name: string;
}

const DEPRECATED_CUE_IDS = new Set(["MA"]);

function resolveStorageUrl(relativePath: string): string {
  return `gs://${CONTENT_STORAGE_BUCKET}/${relativePath}`;
}

function resolveCueUrl(
  cue: { url: string; urlsByVoice?: Record<string, string> },
  voiceId: string
): string {
  return cue.urlsByVoice?.[voiceId] ?? cue.url;
}

// ---------------------------------------------------------------------------
// Shared catalog loading (used by getCatalogs and postMeditations)
// ---------------------------------------------------------------------------

interface CueItem {
  id: string;
  name: string;
  url: string;
  urlsByVoice?: Record<string, string>;
}

interface LoadedCatalogs {
  backgroundSounds: Array<{ id: string; name: string; url: string }>;
  binauralBeats: Array<{
    id: string;
    name: string;
    url: string;
    description: string | null;
  }>;
  cues: CueItem[];
  bodyScanDurations: Record<string, number>;
  voices: VoiceItem[];
}

function loadCatalogs(): LoadedCatalogs {
  const catalogsDir = path.join(__dirname, "../catalogs");

  // Load voices
  let voices: VoiceItem[] = [];
  try {
    const voicesPath = path.join(catalogsDir, "voices.json");
    const voicesData = fs.readFileSync(voicesPath, "utf8");
    const voicesFile = JSON.parse(voicesData) as { voices?: VoiceItem[] };
    voices = voicesFile.voices ?? [];
  } catch (e) {
    functions.logger.warn("loadCatalogs: Failed to load voices.json", e);
  }

  // Background sounds
  const backgroundSounds: Array<{ id: string; name: string; url: string }> = [];
  try {
    const data = fs.readFileSync(
      path.join(catalogsDir, "background_music.json"),
      "utf8"
    );
    const catalog = JSON.parse(data) as RepoCatalogFile;
    for (const m of catalog.models ?? []) {
      backgroundSounds.push({
        id: m.id,
        name: m.name,
        url: m.path ? resolveStorageUrl(m.path) : "",
      });
    }
  } catch (e) {
    functions.logger.warn("loadCatalogs: Failed to parse background_music", e);
  }

  // Binaural beats
  const binauralBeats: Array<{
    id: string;
    name: string;
    url: string;
    description: string | null;
  }> = [];
  try {
    const data = fs.readFileSync(
      path.join(catalogsDir, "binaural_beats.json"),
      "utf8"
    );
    const catalog = JSON.parse(data) as RepoCatalogFile;
    for (const m of catalog.models ?? []) {
      binauralBeats.push({
        id: m.id,
        name: m.name,
        url: m.path ? resolveStorageUrl(m.path) : "",
        description: m.description ?? null,
      });
    }
  } catch (e) {
    functions.logger.warn("loadCatalogs: Failed to parse binaural_beats", e);
  }

  // Cues: merge from cues + body_scan + perfect_breath + i_am_mantra + nostril_focus
  const cueFileNames = CATALOG_FILE_NAMES.slice(2);
  const allModels: RepoCatalogModel[] = [];
  const bodyScanDurations: Record<string, number> = {};

  for (const fileName of cueFileNames) {
    try {
      const data = fs.readFileSync(
        path.join(catalogsDir, `${fileName}.json`),
        "utf8"
      );
      const catalog = JSON.parse(data) as RepoCatalogFile;
      for (const m of catalog.models ?? []) {
        allModels.push(m);
        if (m.duration_minutes != null) {
          bodyScanDurations[m.id] = m.duration_minutes;
        }
      }
    } catch (e) {
      functions.logger.warn(`loadCatalogs: Failed to parse ${fileName}`, e);
    }
  }

  const seen = new Set<string>();
  const cues: CueItem[] = [];
  for (const m of allModels) {
    if (seen.has(m.id) || DEPRECATED_CUE_IDS.has(m.id)) continue;
    seen.add(m.id);
    const url = resolveStorageUrl(m.path);
    const urlsByVoice: Record<string, string> | undefined = m.voices
      ? Object.fromEntries(
          Object.entries(m.voices).map(([k, v]) => [k, resolveStorageUrl(v)])
        )
      : undefined;
    cues.push({
      id: m.id,
      name: m.name,
      url,
      urlsByVoice,
    });
  }

  return {
    backgroundSounds,
    binauralBeats,
    cues,
    bodyScanDurations,
    voices,
  };
}

// ---------------------------------------------------------------------------
// 5. getCatalogs — HTTP GET endpoint for aggregated meditation catalogs
// ---------------------------------------------------------------------------

export const getCatalogs = functions.https.onRequest(
  async (req, res) => {
    // CORS
    res.set("Access-Control-Allow-Origin", "*");
    if (req.method === "OPTIONS") {
      res.set("Access-Control-Allow-Methods", "GET");
      res.set("Access-Control-Allow-Headers", "Content-Type");
      res.status(204).send("");
      return;
    }
    if (req.method !== "GET") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const TAG_CATALOGS = "[Server][Catalogs]";
    const trigger = (req.headers["x-trigger"] as string) ?? "unknown";
    functions.logger.info(
      `${TAG_CATALOGS} getCatalogs: request received trigger=${trigger}`
    );

    try {
      const catalogs = loadCatalogs();
      functions.logger.info(
        `${TAG_CATALOGS} getCatalogs: success sounds=${catalogs.backgroundSounds.length} beats=${catalogs.binauralBeats.length} cues=${catalogs.cues.length} voices=${catalogs.voices.length}`
      );
      res.set("Content-Type", "application/json");
      res.status(200).send(
        JSON.stringify({
          backgroundSounds: catalogs.backgroundSounds,
          binauralBeats: catalogs.binauralBeats,
          cues: catalogs.cues,
          bodyScanDurations: catalogs.bodyScanDurations,
          voices: catalogs.voices,
        })
      );
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      functions.logger.error(`${TAG_CATALOGS} getCatalogs: error - ${errMsg}`);
      res.status(500).send(JSON.stringify({ error: "Internal server error" }));
    }
  }
);

// ---------------------------------------------------------------------------
// 6. postMeditations — HTTP POST endpoint for manual and AI meditation creation
// ---------------------------------------------------------------------------

interface PostMeditationsRequest {
  type: string;
  voiceId?: string;
  duration?: number;
  backgroundSoundId?: string;
  binauralBeatId?: string;
  cues?: Array<{ id: string; trigger: string | number }>;
  prompt?: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  maxDuration?: number;
}

function randomUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

export const postMeditations = functions.runWith({
  secrets: ["OPENAI_API_KEY"],
}).https.onRequest(
  async (req, res) => {
    // CORS
    res.set("Access-Control-Allow-Origin", "*");
    if (req.method === "OPTIONS") {
      res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.set("Access-Control-Allow-Headers", "Content-Type");
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const TAG_MEDITATIONS = "[Server][Meditations]";
    const TAG_AI = "[Server][Meditations-AI]";
    const trigger = (req.headers["x-trigger"] as string) ?? "unknown";

    try {
      const body = req.body as PostMeditationsRequest;
      if (!body || (body.type !== "manual" && body.type !== "ai")) {
        functions.logger.warn(
          `${TAG_MEDITATIONS} postMeditations: validation failed reason=invalid_type type=${body?.type ?? "unknown"} trigger=${trigger}`
        );
        res.status(400).send(
          JSON.stringify({ error: "Invalid request: type must be 'manual' or 'ai'" })
        );
        return;
      }

      // --- AI path ---
      if (body.type === "ai") {
        const prompt = (body.prompt ?? "").trim();
        if (!prompt) {
          functions.logger.warn(
            `${TAG_AI} postMeditations: validation failed reason=empty_prompt trigger=${trigger}`
          );
          res.status(400).send(
            JSON.stringify({ error: "Invalid request: prompt is required for type 'ai'" })
          );
          return;
        }

        const apiKey = (process.env.OPENAI_API_KEY ?? "").trim();
        if (!apiKey) {
          functions.logger.error(`${TAG_AI} postMeditations: OPENAI_API_KEY not configured`);
          res.status(500).send(
            JSON.stringify({ error: "AI service is not configured" })
          );
          return;
        }

        functions.logger.info(
          `${TAG_AI} postMeditations: request received type=ai trigger=${trigger} promptLen=${prompt.length} historyLen=${body.conversationHistory?.length ?? 0} maxDuration=${body.maxDuration ?? "nil"}`
        );

        const catalogs = loadCatalogs();
        const { generateAIMeditation } = await import("./aiMeditation");

        const { meditation, usedFallback } = await generateAIMeditation({
          prompt,
          conversationHistory: body.conversationHistory ?? [],
          maxDuration: body.maxDuration,
          catalogs,
          apiKey,
        });

        const voiceId = body.voiceId ?? "Asaf";

        // Resolve IDs to catalog objects
        const soundMap = new Map(
          catalogs.backgroundSounds.map((s) => [s.id, s])
        );
        const beatMap = new Map(
          catalogs.binauralBeats.map((b) => [b.id, b])
        );
        const cueMap = new Map(catalogs.cues.map((c) => [c.id, c]));

        const backgroundSound = soundMap.get(meditation.backgroundSoundId);
        if (!backgroundSound) {
          functions.logger.warn(
            `${TAG_AI} postMeditations: invalid backgroundSoundId from AI: ${meditation.backgroundSoundId}, using random`
          );
          const nonNone = catalogs.backgroundSounds.filter((s) => s.id !== "None");
          if (nonNone.length === 0) {
            res.status(500).send(
              JSON.stringify({ error: "No background sounds in catalog" })
            );
            return;
          }
          const pick = nonNone[Math.floor(Math.random() * nonNone.length)];
          meditation.backgroundSoundId = pick.id;
        }

        const bg = soundMap.get(meditation.backgroundSoundId)!;
        const bbId = meditation.binauralBeatId ?? "None";
        const binauralBeat =
          bbId && bbId !== "None" ? beatMap.get(bbId) ?? null : null;

        const resolvedCues: Array<{
          id: string;
          name: string;
          url: string;
          trigger: string | number;
        }> = [];
        for (const c of meditation.cues) {
          const cueId = c.id === "SI" ? "INT_GEN_1" : c.id;
          const asset = cueMap.get(cueId);
          if (asset) {
            resolvedCues.push({
              id: asset.id,
              name: asset.name,
              url: resolveCueUrl(asset, voiceId),
              trigger: c.trigger,
            });
          } else if (c.id === "GB") {
            resolvedCues.push({
              id: c.id,
              name: c.id,
              url: "",
              trigger: c.trigger,
            });
          }
        }

        const response = {
          id: randomUUID(),
          title: meditation.title,
          duration: meditation.duration,
          description: meditation.description ?? meditation.title,
          backgroundSound: {
            id: bg.id,
            name: bg.name,
            url: bg.url,
          },
          binauralBeat: binauralBeat
            ? {
                id: binauralBeat.id,
                name: binauralBeat.name,
                url: binauralBeat.url,
                description: binauralBeat.description ?? undefined,
              }
            : null,
          cues: resolvedCues,
        };

        functions.logger.info(
          `${TAG_AI} postMeditations: success id=${response.id} duration=${meditation.duration} title=${meditation.title} cues=${resolvedCues.length} usedFallback=${usedFallback} trigger=${trigger}`
        );
        res.set("Content-Type", "application/json");
        res.status(200).send(JSON.stringify(response));
        return;
      }

      // --- Manual path ---

      const duration = body.duration ?? 0;
      const voiceId = body.voiceId ?? "Asaf";
      const backgroundSoundId = body.backgroundSoundId ?? "";
      const binauralBeatId = body.binauralBeatId ?? "None";
      const cues = body.cues ?? [];

      functions.logger.info(
        `${TAG_MEDITATIONS} postMeditations: request received type=manual trigger=${trigger} duration=${duration} cueCount=${cues.length} bs=${backgroundSoundId} bb=${binauralBeatId} voiceId=${voiceId}`
      );

      // Validate duration (1-60)
      if (typeof duration !== "number" || duration < 1 || duration > 60) {
        functions.logger.warn(
          `${TAG_MEDITATIONS} postMeditations: validation failed type=manual reason=invalid_duration trigger=${trigger}`
        );
        res.status(400).send(
          JSON.stringify({ error: "Invalid duration: must be 1-60" })
        );
        return;
      }

      const catalogs = loadCatalogs();

      // Validate backgroundSoundId
      const soundMap = new Map(
        catalogs.backgroundSounds.map((s) => [s.id, s])
      );
      const backgroundSound = soundMap.get(backgroundSoundId);
      if (!backgroundSound) {
        functions.logger.warn(
          `${TAG_MEDITATIONS} postMeditations: validation failed type=manual reason=invalid_backgroundSoundId trigger=${trigger}`
        );
        res.status(400).send(
          JSON.stringify({
            error: `Invalid backgroundSoundId: ${backgroundSoundId}`,
          })
        );
        return;
      }

      // Validate binauralBeatId (optional or "None")
      let binauralBeat: { id: string; name: string; url: string; description: string | null } | null = null;
      if (binauralBeatId && binauralBeatId !== "None") {
        const beatMap = new Map(
          catalogs.binauralBeats.map((b) => [b.id, b])
        );
        const found = beatMap.get(binauralBeatId);
        if (!found) {
          functions.logger.warn(
            `${TAG_MEDITATIONS} postMeditations: validation failed type=manual reason=invalid_binauralBeatId trigger=${trigger}`
          );
          res.status(400).send(
            JSON.stringify({ error: `Invalid binauralBeatId: ${binauralBeatId}` })
          );
          return;
        }
        binauralBeat = found;
      }

      // Validate cues
      const cueMap = new Map(catalogs.cues.map((c) => [c.id, c]));
      const resolvedCues: Array<{
        id: string;
        name: string;
        url: string;
        trigger: string | number;
      }> = [];

      for (const c of cues) {
        if (!c || typeof c.id !== "string" || c.trigger === undefined) {
          functions.logger.warn(
            `${TAG_MEDITATIONS} postMeditations: validation failed type=manual reason=invalid_cue trigger=${trigger}`
          );
          res.status(400).send(
            JSON.stringify({ error: "Invalid cue: each cue needs id and trigger" })
          );
          return;
        }
        const cueAsset = cueMap.get(c.id);
        if (!cueAsset) {
          functions.logger.warn(
            `${TAG_MEDITATIONS} postMeditations: validation failed type=manual reason=invalid_cue_id cue=${c.id} trigger=${trigger}`
          );
          res.status(400).send(
            JSON.stringify({ error: `Invalid cue id: ${c.id}` })
          );
          return;
        }
        const cueTrigger = c.trigger;
        const validTrigger =
          cueTrigger === "start" ||
          cueTrigger === "end" ||
          (typeof cueTrigger === "number" && cueTrigger >= 0 && cueTrigger <= duration);
        if (!validTrigger) {
          functions.logger.warn(
            `${TAG_MEDITATIONS} postMeditations: validation failed type=manual reason=invalid_trigger cue=${c.id} trigger=${trigger}`
          );
          res.status(400).send(
            JSON.stringify({
              error: `Invalid trigger for cue ${c.id}: must be 'start', 'end', or a number 0-${duration}`,
            })
          );
          return;
        }
        resolvedCues.push({
          id: cueAsset.id,
          name: cueAsset.name,
          url: resolveCueUrl(cueAsset, voiceId),
          trigger: cueTrigger,
        });
      }

      const response = {
        id: randomUUID(),
        title: null,
        duration,
        description: null,
        backgroundSound: {
          id: backgroundSound.id,
          name: backgroundSound.name,
          url: backgroundSound.url,
        },
        binauralBeat: binauralBeat
          ? {
              id: binauralBeat.id,
              name: binauralBeat.name,
              url: binauralBeat.url,
              description: binauralBeat.description ?? undefined,
            }
          : null,
        cues: resolvedCues,
      };

      functions.logger.info(
        `${TAG_MEDITATIONS} postMeditations: success type=manual id=${response.id} duration=${duration} trigger=${trigger}`
      );
      res.set("Content-Type", "application/json");
      res.status(200).send(JSON.stringify(response));
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      functions.logger.error(
        `${TAG_MEDITATIONS} postMeditations: error type=manual trigger=${trigger} - ${errMsg}`
      );
      res.status(500).send(JSON.stringify({ error: "Internal server error" }));
    }
  }
);

// ---------------------------------------------------------------------------
// 7. postAIRequest — Unified AI endpoint (classify, route, respond)
// ---------------------------------------------------------------------------

const TAG_AI_REQUEST = "[Server][AI]";

export const postAIRequest = functions.runWith({
  secrets: ["OPENAI_API_KEY"],
}).https.onRequest(
  async (req, res) => {
    res.set("Access-Control-Allow-Origin", "*");
    if (req.method === "OPTIONS") {
      res.set("Access-Control-Allow-Methods", "POST, OPTIONS");
      res.set("Access-Control-Allow-Headers", "Content-Type, X-Trigger");
      res.status(204).send("");
      return;
    }
    if (req.method !== "POST") {
      res.status(405).send("Method Not Allowed");
      return;
    }

    const trigger = (req.headers["x-trigger"] as string) ?? "unknown";

    try {
      const body = req.body as { prompt?: string; conversationHistory?: Array<{ role: string; content: string }>; context?: unknown };
      const apiKey = (process.env.OPENAI_API_KEY ?? "").trim();
      if (!apiKey) {
        functions.logger.error(`${TAG_AI_REQUEST} OPENAI_API_KEY not configured`);
        res.status(500).send(JSON.stringify({ error: "AI service is not configured" }));
        return;
      }

      const result = await processAIRequest(
        {
          prompt: body.prompt ?? "",
          voiceId: (body as { voiceId?: string }).voiceId,
          conversationHistory: body.conversationHistory,
          context: body.context as {
            pathInfo?: { nextStepTitle: string; completedCount: number; totalCount: number } | null;
            exploreInfo?: { sessionTitle: string; timeOfDay: string } | null;
            lastMeditationDuration?: number;
          },
        },
        () => Promise.resolve(loadCatalogs()),
        apiKey
      );

      res.set("Content-Type", "application/json");
      res.status(200).send(JSON.stringify(result));
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      functions.logger.error(`${TAG_AI_REQUEST} error trigger=${trigger} - ${errMsg}`);
      res.status(500).send(JSON.stringify({ error: "Internal server error" }));
    }
  }
);
