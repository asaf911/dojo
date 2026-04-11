/**
 * Unified AI request handler: classify intent, route, and return response.
 * Replaces client-side AI logic with a single server endpoint.
 */

import * as functions from "firebase-functions";
import { generateAIMeditation } from "./aiMeditation";
import type { LoadedCatalogs } from "./aiMeditation";
import type { FractionalCompositionContext } from "./meditationThemes";
import {
  applyPracticeRelativeIntroPrefix,
  expandFractionalCues,
} from "./fractionalComposer";
import { normalizeFractionalSurfaceCueIdsForProd } from "./fractionalSurfaceCueNormalize";
import { useFractionalModulesInCatalogsAndAI } from "./deploymentMode";

const TAG = "[Server][AI]";

export interface AIRequestContext {
  pathInfo?: {
    nextStepTitle: string;
    completedCount: number;
    totalCount: number;
  } | null;
  exploreInfo?: {
    sessionTitle: string;
    timeOfDay: string;
  } | null;
  lastMeditationDuration?: number;
  /** Last N background sound IDs used; server down-weights these for variety */
  recentBackgroundSounds?: string[];
  /** Optional canonical theme tags (morning, evening, noon, night, sleep, gratitude); merged with explore + prompt */
  meditationThemes?: string[];
}

export interface AIRequestBody {
  prompt: string;
  voiceId?: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  context?: AIRequestContext;
}

/** History sub-intent: which specific query the client should run. AI interprets user meaning. */
export type HistoryQueryType =
  | "last_session_nadir"   // Lowest HR during most recent session
  | "all_time_nadir"       // Lowest HR during any session (all-time)
  | "most_recent_session" // General info about last session
  | "heart_rate_trend"    // HR averages/trends over recent sessions
  | "total_stats"         // Total sessions, time, etc.
  | "other";              // Fallback: client uses keyword matching

export interface AIRequestResponse {
  intent: string;
  content:
    | { type: "meditation"; meditation: MeditationPackage }
    | { type: "text"; text: string }
    | { type: "history"; historyQueryType?: HistoryQueryType };
}

interface MeditationPackage {
  id: string;
  title: string | null;
  duration: number;
  /** Practice + intro prelude (seconds). */
  playbackDurationSec?: number;
  description: string | null;
  backgroundSound: { id: string; name: string; url: string };
  binauralBeat: {
    id: string;
    name: string;
    url: string;
    description?: string;
  } | null;
  cues: Array<{
    id: string;
    name: string;
    url: string;
    trigger: string | number;
  }>;
}

const VALID_INTENTS = [
  "meditation",
  "history",
  "explain",
  "conversation",
  "app_help",
  "out_of_scope",
  "path_guidance",
  "explore_guidance",
] as const;

async function callOpenAI(
  userPrompt: string,
  systemPrompt: string,
  conversationHistory: Array<{ role: string; content: string }>,
  apiKey: string
): Promise<string> {
  const messages: Array<{ role: string; content: string }> = [
    { role: "system", content: systemPrompt },
    ...conversationHistory,
    { role: "user", content: userPrompt },
  ];

  const response = await fetch("https://api.openai.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model: "gpt-4o-mini",
      messages,
      max_tokens: 300,
      temperature: 0.7,
    }),
  });

  const body = await response.text();
  if (!response.ok) {
    throw new Error(`OpenAI API error ${response.status}: ${body}`);
  }

  const parsed = JSON.parse(body);
  const content = parsed?.choices?.[0]?.message?.content;
  if (!content || typeof content !== "string") {
    throw new Error("No response content from OpenAI");
  }
  return content;
}

function classifyIntent(
  prompt: string,
  conversationHistory: Array<{ role: string; content: string }>,
  apiKey: string
): Promise<string> {
  const systemPrompt = `You are an intent classifier for a meditation app. Classify the user's latest message intent as exactly one of:
- meditation: user wants to create or MODIFY a meditation (e.g., change body scan to 7 minutes, 10 minute sleep meditation)
- history: user asks about THEIR personal meditation data (their heart rate, their sessions, their progress, their statistics, their averages, their history)
- explain: user asks a GENERAL question about meditation concepts (definition, benefits, how to meditate, why meditate) - NOT about their personal data
- app_help: app/account/billing/support questions (cancel subscription, pricing, restore purchase, notifications)
- out_of_scope: non-app, non-meditation requests (weather, call/text/email someone, jokes, web queries)
- path_guidance: user asks what to do next, where to begin, what's their next step, guidance on their meditation journey, what to practice
- explore_guidance: user asks for a pre-recorded session, specifically mentions "pre-recorded", "prerecorded", "guided session", or "from library"
- conversation: greetings/small talk or generic chat that isn't clearly any of the above

IMPORTANT:
- If user asks about "my heart rate", "my sessions", "my average", "my progress", "my history", "how many sessions", "when did I" - classify as "history".
- If user asks "what should I do", "what's next", "where do I begin", "what do I do next", "next step", "guide me", "what to practice", "help me start" - classify as "path_guidance".
- If user mentions "pre-recorded", "prerecorded", "guided session", "from library", "ready-made" - classify as "explore_guidance".

Respond ONLY with compact JSON on one line: {"intent":"meditation|history|explain|app_help|out_of_scope|path_guidance|explore_guidance|conversation"}
Do not include any extra text.`;

  return callOpenAI(prompt, systemPrompt, conversationHistory, apiKey).then(
    (content) => {
      let s = content.trim();
      if (s.startsWith("```json")) s = s.slice(7);
      if (s.startsWith("```")) s = s.slice(3);
      if (s.endsWith("```")) s = s.slice(0, -3);
      s = s.trim();
      const first = s.indexOf("{");
      const last = s.lastIndexOf("}");
      if (first >= 0 && last > first) s = s.slice(first, last + 1);
      const parsed = JSON.parse(s) as { intent?: string };
      const v = (parsed.intent ?? "").toLowerCase();
      if (VALID_INTENTS.includes(v as (typeof VALID_INTENTS)[number])) {
        return v;
      }
      return heuristicClassify(prompt);
    }
  ).catch(() => heuristicClassify(prompt));
}

function heuristicClassify(prompt: string): string {
  const lower = prompt.toLowerCase();

  const pathGuidanceSignals = [
    "what should i do", "what's next", "whats next", "what do i do",
    "where do i begin", "where do i start", "where should i start",
    "next step", "what's the next step", "whats the next step",
    "guide me", "help me start", "what now", "what to practice",
    "what to do next", "continue my journey", "what's next in my path",
  ];
  if (pathGuidanceSignals.some((sig) => lower.includes(sig))) return "path_guidance";

  const exploreGuidanceSignals = [
    "pre-recorded", "prerecorded", "pre recorded", "guided session",
    "from library", "ready-made", "ready made",
  ];
  if (exploreGuidanceSignals.some((sig) => lower.includes(sig))) return "explore_guidance";

  const historySignals = [
    "my heart rate", "my hr", "my bpm", "my session", "my meditation",
    "my average", "my avg", "my history", "my progress", "my stats",
    "my statistics", "my trend", "how many session", "how many meditation",
    "how long have i", "when did i", "which session", "lowest heart",
    "highest heart", "best session",
  ];
  if (historySignals.some((sig) => lower.includes(sig))) return "history";

  const isQuestion = lower.endsWith("?");
  const explainStarts = ["what is", "how do", "how does", "why", "explain", "tell me about", "what's", "whats"];
  if (isQuestion && explainStarts.some((s) => lower.startsWith(s)) && !historySignals.some((sig) => lower.includes(sig))) {
    return "explain";
  }

  const appHelp = ["subscription", "cancel", "billing", "price", "pricing", "restore", "purchase", "account", "login", "log in", "sign in", "password", "notification", "terms", "privacy", "support", "contact"];
  if (appHelp.some((sig) => lower.includes(sig))) return "app_help";

  const oos = ["weather", "forecast", "temperature", "call", "text", "email", "message", "facetime", "maps", "route", "restaurant", "deliver", "order", "uber", "lyft", "news", "stock", "price of", "btc", "ethereum", "joke", "poem", "code this", "calculate", "math"];
  if (oos.some((sig) => lower.includes(sig))) return "out_of_scope";

  const modifyHints = ["change", "set", "make", "switch", "update", "replace", "remove", "add", "extend", "shorten", "longer", "shorter", "increase", "decrease", "edit", "adjust", "tweak", "body scan", "bs"];
  if (modifyHints.some((sig) => lower.includes(sig))) return "meditation";

  return "conversation";
}

const VALID_HISTORY_QUERY_TYPES: HistoryQueryType[] = [
  "last_session_nadir",
  "all_time_nadir",
  "most_recent_session",
  "heart_rate_trend",
  "total_stats",
  "other",
];

async function classifyHistorySubIntent(
  prompt: string,
  conversationHistory: Array<{ role: string; content: string }>,
  apiKey: string
): Promise<HistoryQueryType> {
  const systemPrompt = `You are a classifier for a meditation app's history queries. The user has asked about their personal meditation/session data. Classify what they want to know into exactly one of:

- last_session_nadir: User asks about the LOWEST heart rate DURING their most recent/last session (e.g. "what was my lowest in the last session", "nadir in my last meditation", "lowest hr last time", "what was the nadir" when previous message was about last session)
- all_time_nadir: User asks about their LOWEST heart rate ever across ALL sessions (e.g. "all time lowest", "lowest ever", "best relaxation", "my lowest heart rate during any session")
- most_recent_session: User asks about their last/most recent session in general (not specifically nadir)
- heart_rate_trend: User asks about averages, trends, how HR changes over time
- total_stats: User asks about total sessions, how many, how much time, overall stats
- other: Anything else (client will use keyword fallback)

IMPORTANT:
- "What was my lowest in the last session?" -> last_session_nadir
- "But what was the nadir?" (after asking about last session) -> last_session_nadir (conversation context)
- "What was my all-time lowest?" or "lowest ever" -> all_time_nadir
- "Nadir" alone with no "last/previous" context -> all_time_nadir
- Consider the conversation history: if the previous exchange was about the last session, "the nadir" likely means last session nadir

Respond ONLY with compact JSON: {"historyQueryType":"last_session_nadir|all_time_nadir|most_recent_session|heart_rate_trend|total_stats|other"}`;

  try {
    const content = await callOpenAI(prompt, systemPrompt, conversationHistory, apiKey);
    let s = content.trim();
    if (s.startsWith("```json")) s = s.slice(7);
    if (s.startsWith("```")) s = s.slice(3);
    if (s.endsWith("```")) s = s.slice(0, -3);
    s = s.trim();
    const first = s.indexOf("{");
    const last = s.lastIndexOf("}");
    if (first >= 0 && last > first) s = s.slice(first, last + 1);
    const parsed = JSON.parse(s) as { historyQueryType?: string };
    const v = (parsed.historyQueryType ?? "other").toLowerCase().replace(/-/g, "_");
    const match = VALID_HISTORY_QUERY_TYPES.find((t) => t === v);
    return match ?? "other";
  } catch {
    return "other";
  }
}

function randomUUID(): string {
  return "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === "x" ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

function resolveCueUrl(
  cue: { url: string; urlsByVoice?: Record<string, string> },
  voiceId: string
): string {
  return cue.urlsByVoice?.[voiceId] ?? cue.url;
}

function buildMeditationPackage(
  meditation: {
    duration: number;
    backgroundSoundId: string;
    binauralBeatId?: string | null;
    cues: Array<{ id: string; trigger: string; durationMinutes?: number }>;
    title?: string | null;
    description?: string | null;
  },
  catalogs: LoadedCatalogs,
  voiceId: string,
  fractionalCompositionContext?: FractionalCompositionContext
): MeditationPackage {
  const soundMap = new Map(catalogs.backgroundSounds.map((s) => [s.id, s]));
  const beatMap = new Map(catalogs.binauralBeats.map((b) => [b.id, b]));
  const cueMap = new Map(catalogs.cues.map((c) => [c.id, c]));

  let bgId = meditation.backgroundSoundId;
  let bg = soundMap.get(bgId);
  if (!bg) {
    const nonNone = catalogs.backgroundSounds.filter((s) => s.id !== "None");
    const pick = nonNone[Math.floor(Math.random() * nonNone.length)];
    bgId = pick?.id ?? nonNone[0]?.id ?? "SP";
    bg =
      catalogs.backgroundSounds.find((s) => s.id === bgId) ?? {
        id: "SP",
        name: "Spa",
        url: "",
      };
  }

  const bbId = meditation.binauralBeatId ?? "None";
  const binauralBeat = bbId && bbId !== "None" ? beatMap.get(bbId) ?? null : null;

  const normalizedCues = useFractionalModulesInCatalogsAndAI()
    ? meditation.cues
    : normalizeFractionalSurfaceCueIdsForProd(
        meditation.cues,
        meditation.duration
      );

  const resolvedCues: Array<{
    id: string;
    name: string;
    url: string;
    trigger: string | number;
    durationMinutes?: number;
  }> = [];
  for (const c of normalizedCues) {
    const cueId =
      c.id === "SI"
        ? useFractionalModulesInCatalogsAndAI()
          ? "INT_FRAC"
          : "INT_GEN_1"
        : c.id;
    const asset = cueMap.get(cueId);
    if (asset) {
      resolvedCues.push({
        id: asset.id,
        name: asset.name,
        url: resolveCueUrl(asset, voiceId),
        trigger: c.trigger,
        durationMinutes:
          typeof c.durationMinutes === "number" && c.durationMinutes > 0
            ? c.durationMinutes
            : undefined,
      });
    } else if (c.id === "GB") {
      resolvedCues.push({ id: c.id, name: c.id, url: "", trigger: c.trigger });
    }
  }

  const timelineMeta = applyPracticeRelativeIntroPrefix(
    resolvedCues,
    meditation.duration
  );
  // Expand fractional modules (e.g. NF_FRAC) into second-precision clips
  const expandedCues = expandFractionalCues(
    resolvedCues,
    meditation.duration,
    voiceId,
    fractionalCompositionContext
  );

  return {
    id: randomUUID(),
    title: meditation.title ?? null,
    duration: meditation.duration,
    playbackDurationSec: timelineMeta.sessionDurationSec,
    description: meditation.description ?? meditation.title ?? null,
    backgroundSound: { id: bg.id, name: bg.name, url: bg.url },
    binauralBeat: binauralBeat
      ? { id: binauralBeat.id, name: binauralBeat.name, url: binauralBeat.url, description: binauralBeat.description ?? undefined }
      : null,
    cues: expandedCues,
  };
}

export async function processAIRequest(
  body: AIRequestBody,
  loadCatalogs: () => Promise<LoadedCatalogs>,
  apiKey: string
): Promise<AIRequestResponse> {
  const prompt = (body.prompt ?? "").trim();
  if (!prompt) {
    throw new Error("Invalid request: prompt is required");
  }

  const conversationHistory = body.conversationHistory ?? [];
  const context = body.context ?? {};

  functions.logger.info(`${TAG} request received promptLen=${prompt.length} historyLen=${conversationHistory.length}`);

  const intent = await classifyIntent(prompt, conversationHistory, apiKey);
  functions.logger.info(`${TAG} classified intent=${intent}`);

  if (intent === "history") {
    const historyQueryType = await classifyHistorySubIntent(prompt, conversationHistory, apiKey);
    functions.logger.info(`${TAG} history sub-intent=${historyQueryType}`);
    return { intent: "history", content: { type: "history", historyQueryType } };
  }

  if (intent === "meditation") {
    const catalogs = await loadCatalogs();
    const voiceId = body.voiceId ?? "Asaf";
    const { meditation, usedFallback, fractionalCompositionContext } =
      await generateAIMeditation({
        prompt,
        conversationHistory,
        catalogs,
        apiKey,
        lastMeditationDuration: context.lastMeditationDuration,
        recentBackgroundSounds: context.recentBackgroundSounds,
        exploreTimeOfDay: context.exploreInfo?.timeOfDay ?? null,
        clientMeditationThemes: context.meditationThemes,
      });
    const pkg = buildMeditationPackage(
      meditation,
      catalogs,
      voiceId,
      fractionalCompositionContext
    );
    functions.logger.info(`${TAG} success intent=meditation id=${pkg.id} duration=${pkg.duration} usedFallback=${usedFallback}`);
    return { intent: "meditation", content: { type: "meditation", meditation: pkg } };
  }

  if (intent === "path_guidance" && context.pathInfo) {
    const { nextStepTitle, completedCount, totalCount } = context.pathInfo;
    const progressContext = completedCount === 0 ? "This is their first step." : `They've done ${completedCount} of ${totalCount} steps.`;
    const systemPrompt = `Write ONE simple sentence to introduce the next meditation lesson.

RULES:
- Maximum 10 words
- Simple everyday language, like talking to a friend
- NO spiritual or poetic language
- NO words like: journey, essence, path, explore, discover, embrace
- Just be helpful and normal

CONTEXT:
- User asked: "${prompt}"
- Next lesson: "${nextStepTitle}"
- ${progressContext}

GOOD examples: "Here's a good one for you." / "Try this next." / "This one's worth checking out."
BAD examples: "Begin your journey..." / "Explore the essence..." / "Embrace this step..."

Output ONLY the sentence.`;
    const text = await callOpenAI("Generate the sentence.", systemPrompt, [], apiKey);
    const trimmed = text.trim();
    const result = trimmed.length >= 5 ? trimmed : "Try this one.";
    functions.logger.info(`${TAG} success intent=path_guidance`);
    return { intent: "path_guidance", content: { type: "text", text: result } };
  }

  if (intent === "explore_guidance" && context.exploreInfo) {
    const { sessionTitle, timeOfDay } = context.exploreInfo;
    const systemPrompt = `Write ONE simple sentence to introduce a pre-recorded meditation session.

RULES:
- Maximum 12 words
- Simple everyday language, like talking to a friend
- NO spiritual or poetic language
- NO words like: journey, essence, explore, discover, embrace
- Just be helpful and normal
- Reference the time of day naturally if relevant

CONTEXT:
- User asked: "${prompt}"
- Session title: "${sessionTitle}"
- Time of day: ${timeOfDay}

GOOD examples: "Here's a great ${timeOfDay} session for you." / "Try this one." / "This should be perfect right now."
BAD examples: "Embark on a journey..." / "Discover the essence..." / "Embrace this moment..."

Output ONLY the sentence.`;
    const text = await callOpenAI("Generate the sentence.", systemPrompt, [], apiKey);
    const trimmed = text.trim();
    const result = trimmed.length >= 5 ? trimmed : "Here's a session for you.";
    functions.logger.info(`${TAG} success intent=explore_guidance`);
    return { intent: "explore_guidance", content: { type: "text", text: result } };
  }

  if (intent === "explain") {
    const systemPrompt = `You are a helpful meditation guide. Answer the user's question clearly and concisely in 2-4 sentences.
Avoid lists or bullet points. Do not include code blocks.
Keep it practical and friendly.`;
    const text = await callOpenAI(prompt, systemPrompt, conversationHistory, apiKey);
    const trimmed = text.trim();
    const words = trimmed.split(/\s+/);
    const limited = words.length <= 120 ? trimmed : words.slice(0, 120).join(" ");
    functions.logger.info(`${TAG} success intent=explain`);
    return { intent: "explain", content: { type: "text", text: limited } };
  }

  if (intent === "app_help" || intent === "out_of_scope") {
    let persona = "You are a friendly meditation guide called Sensei. Keep responses to 1-3 sentences. Kindly steer the user back to creating a meditation when appropriate.";
    if (intent === "app_help") {
      persona += "\nIf the user asks for app/account/billing help, explain briefly what they can do in-app (e.g., Settings -> Subscription) and suggest contacting support via the app if needed.";
    } else {
      persona += "\nIf the request is outside meditation or app help (e.g., weather, calling friends), politely say it's out of scope and suggest crafting a meditation instead.";
    }
    const text = await callOpenAI(prompt, persona, conversationHistory, apiKey);
    functions.logger.info(`${TAG} success intent=${intent}`);
    return { intent, content: { type: "text", text: text.trim() } };
  }

  if (intent === "path_guidance" || intent === "explore_guidance") {
    const text = await callOpenAI(
      prompt,
      "You are a friendly meditation guide called Sensei. Keep responses to 1-3 sentences. Kindly steer the user back to creating a meditation when appropriate.",
      conversationHistory,
      apiKey
    );
    functions.logger.info(`${TAG} success intent=${intent} fallback to conversation`);
    return { intent, content: { type: "text", text: text.trim() } };
  }

  const persona = "You are a friendly meditation guide called Sensei. Keep responses to 1-3 sentences. Kindly steer the user back to creating a meditation when appropriate.";
  const text = await callOpenAI(prompt, persona, conversationHistory, apiKey);
  functions.logger.info(`${TAG} success intent=conversation`);
  return { intent: "conversation", content: { type: "text", text: text.trim() } };
}
