import * as functions from "firebase-functions";
import * as admin from "firebase-admin";
import {createHash} from "crypto";

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

const CATALOG_PATHS = [
  "modules/background_music/background_music_models.json",
  "modules/binaural_beats/binaural_beats_models.json",
  "modules/cues/cues_models.json",
  "modules/body_scan/body_scan_models.json",
  "modules/perfect_breath/perfect_breath_models.json",
  "modules/i_am_mantra/i_am_mantra_models.json",
  "modules/nostril_focus/nostril_focus_models.json",
] as const;

interface CatalogModel {
  id: string;
  name: string;
  audio: { url: string };
  duration_minutes?: number;
  description?: string;
}

interface CatalogFile {
  version?: string;
  models: CatalogModel[];
}

const DEPRECATED_CUE_IDS = new Set(["MA"]);

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

    try {
      const bucket = admin.storage().bucket();
      const downloads = await Promise.all(
        CATALOG_PATHS.map(async (path) => {
          try {
            const [contents] = await bucket.file(path).download();
            return { path, data: contents.toString("utf8") };
          } catch (err) {
            functions.logger.warn(`getCatalogs: Failed to read ${path}:`, err);
            return { path, data: null };
          }
        })
      );

      const byPath = Object.fromEntries(
        downloads.map((d) => [d.path, d.data])
      );

      // Background sounds
      const bgPath = CATALOG_PATHS[0];
      const bgData = byPath[bgPath];
      const backgroundSounds: Array<{ id: string; name: string; url: string }> =
        [];
      if (bgData) {
        try {
          const catalog = JSON.parse(bgData) as CatalogFile;
          for (const m of catalog.models ?? []) {
            backgroundSounds.push({
              id: m.id,
              name: m.name,
              url: m.audio?.url ?? "",
            });
          }
        } catch (e) {
          functions.logger.warn("getCatalogs: Failed to parse background music", e);
        }
      }

      // Binaural beats
      const bbPath = CATALOG_PATHS[1];
      const bbData = byPath[bbPath];
      const binauralBeats: Array<{
        id: string;
        name: string;
        url: string;
        description: string | null;
      }> = [];
      if (bbData) {
        try {
          const catalog = JSON.parse(bbData) as CatalogFile;
          for (const m of catalog.models ?? []) {
            binauralBeats.push({
              id: m.id,
              name: m.name,
              url: m.audio?.url ?? "",
              description: m.description ?? null,
            });
          }
        } catch (e) {
          functions.logger.warn("getCatalogs: Failed to parse binaural beats", e);
        }
      }

      // Cues: merge from cues + body_scan + perfect_breath + i_am_mantra + nostril_focus
      const cuePaths = CATALOG_PATHS.slice(2);
      const allModels: CatalogModel[] = [];
      const bodyScanDurations: Record<string, number> = {};

      for (const path of cuePaths) {
        const data = byPath[path];
        if (!data) continue;
        try {
          const catalog = JSON.parse(data) as CatalogFile;
          for (const m of catalog.models ?? []) {
            allModels.push(m);
            if (m.duration_minutes != null) {
              bodyScanDurations[m.id] = m.duration_minutes;
            }
          }
        } catch (e) {
          functions.logger.warn(`getCatalogs: Failed to parse ${path}`, e);
        }
      }

      const seen = new Set<string>();
      const cues: Array<{ id: string; name: string; url: string }> = [];
      for (const m of allModels) {
        if (seen.has(m.id) || DEPRECATED_CUE_IDS.has(m.id)) continue;
        seen.add(m.id);
        cues.push({
          id: m.id,
          name: m.name,
          url: m.audio?.url ?? "",
        });
      }

      res.set("Content-Type", "application/json");
      res.status(200).send(
        JSON.stringify({
          backgroundSounds,
          binauralBeats,
          cues,
          bodyScanDurations,
        })
      );
    } catch (err) {
      const errMsg = err instanceof Error ? err.message : String(err);
      functions.logger.error("getCatalogs: Unexpected error:", errMsg);
      res.status(500).send(JSON.stringify({ error: "Internal server error" }));
    }
  }
);
