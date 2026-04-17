import { createHash } from "crypto";
import * as functions from "firebase-functions";
import { createTransport } from "nodemailer";

const TAG = "[Server][SupportContact]";

/** Per-instance rolling window (resets on cold start; no Firestore dependency). */
const MAX_SUBMISSIONS_PER_HOUR = 10;
const RATE_WINDOW_MS = 60 * 60 * 1000;
const rateBucket = new Map<string, { windowStart: number; count: number }>();
const RATE_MAP_MAX_KEYS = 2000;

const MAX_NAME_LEN = 200;
const MAX_MESSAGE_LEN = 10_000;

function sha256(input: string): string {
  return createHash("sha256").update(input).digest("hex");
}

function clientIp(req: functions.https.Request): string {
  const xff = req.headers["x-forwarded-for"];
  if (typeof xff === "string" && xff.length > 0) {
    return xff.split(",")[0]?.trim() ?? "unknown";
  }
  const xReal = req.headers["x-real-ip"];
  if (typeof xReal === "string" && xReal.length > 0) {
    return xReal.trim();
  }
  return req.socket?.remoteAddress ?? "unknown";
}

/** Pragmatic check; not exhaustive RFC validation. */
function isPlausibleEmail(email: string): boolean {
  if (email.length > 254) return false;
  return /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email);
}

function escapeHtml(s: string): string {
  return s
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;");
}

function checkRateLimitInMemory(ip: string): boolean {
  const now = Date.now();
  const key = sha256(`support_contact:${ip}`);
  let entry = rateBucket.get(key);
  if (!entry || now - entry.windowStart >= RATE_WINDOW_MS) {
    entry = { windowStart: now, count: 1 };
  } else {
    entry.count += 1;
  }
  rateBucket.set(key, entry);

  if (rateBucket.size > RATE_MAP_MAX_KEYS) {
    const cutoff = now - RATE_WINDOW_MS;
    for (const [k, v] of rateBucket) {
      if (v.windowStart < cutoff) rateBucket.delete(k);
    }
  }

  return entry.count <= MAX_SUBMISSIONS_PER_HOUR;
}

export async function supportContactHttps(
  req: functions.https.Request,
  res: functions.Response
): Promise<void> {
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

  res.set("Content-Type", "application/json");

  const smtpUser = (process.env.WORKSPACE_SMTP_USER ?? "").trim();
  const smtpPass = (process.env.WORKSPACE_SMTP_APP_PASSWORD ?? "").trim();
  const inbox = (process.env.SUPPORT_INBOX_EMAIL ?? "").trim();

  if (!smtpUser || !smtpPass || !inbox) {
    functions.logger.error(`${TAG} missing SMTP or inbox secrets`);
    res.status(500).send(JSON.stringify({ error: "Email is not configured." }));
    return;
  }

  const raw = req.body as { name?: unknown; email?: unknown; message?: unknown };
  const name =
    typeof raw?.name === "string" ? raw.name.trim().slice(0, MAX_NAME_LEN) : "";
  const email = typeof raw?.email === "string" ? raw.email.trim() : "";
  const message =
    typeof raw?.message === "string"
      ? raw.message.trim().slice(0, MAX_MESSAGE_LEN)
      : "";

  if (!email || !isPlausibleEmail(email)) {
    res.status(400).send(JSON.stringify({ error: "A valid email is required." }));
    return;
  }

  const ip = clientIp(req);
  const allowed = checkRateLimitInMemory(ip);

  if (!allowed) {
    functions.logger.warn(`${TAG} rate limited ipHash=${sha256(ip)}`);
    res.status(429).send(JSON.stringify({ error: "Too many submissions. Try again later." }));
    return;
  }

  const textLines = [
    name ? `Name: ${name}` : "Name: (not provided)",
    `Email: ${email}`,
    "",
    message || "(No message provided)",
  ];
  const textBody = textLines.join("\n");
  const htmlBody = `<pre style="font-family:system-ui,sans-serif;white-space:pre-wrap">${escapeHtml(
    textBody
  )}</pre>`;

  const transporter = createTransport({
    host: "smtp.gmail.com",
    port: 465,
    secure: true,
    auth: {
      user: smtpUser,
      pass: smtpPass,
    },
  });

  try {
    await transporter.sendMail({
      from: `"Dojo website" <${smtpUser}>`,
      to: inbox,
      replyTo: email,
      subject: "Dojo support request (web form)",
      text: textBody,
      html: htmlBody,
    });
    functions.logger.info(
      `${TAG} sent ok toInbox=${inbox} replyToLen=${email.length} msgLen=${message.length}`
    );
    res.status(200).send(JSON.stringify({ ok: true }));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    functions.logger.error(`${TAG} sendMail failed: ${msg}`);
    res.status(500).send(JSON.stringify({ error: "Could not send message. Try again later." }));
  }
}
