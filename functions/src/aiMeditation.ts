/**
 * AI meditation generation: build prompts, call OpenAI, parse, validate, fallback.
 * Ported from iOS SimplifiedAIService.
 */

import * as functions from "firebase-functions";

// eslint-disable-next-line @typescript-eslint/no-var-requires
const guidelines = require("./ai_composition_guidelines.json") as {
  module_type_classifications?: { trigger_cue?: { modules?: string[] } };
  session_templates?: Record<string, { cues?: Array<{ id: string; trigger: string }> }>;
};

export interface AIGeneratedTimer {
  duration: number;
  backgroundSoundId: string;
  binauralBeatId?: string | null;
  cues: Array<{ id: string; trigger: string }>;
  title: string;
  description?: string | null;
}

export interface LoadedCatalogs {
  backgroundSounds: Array<{ id: string; name: string; url: string }>;
  binauralBeats: Array<{
    id: string;
    name: string;
    url: string;
    description: string | null;
  }>;
  cues: Array<{ id: string; name: string; url: string }>;
  bodyScanDurations: Record<string, number>;
}

const TAG_AI = "[Server][Meditations-AI]";

function buildSystemPrompt(catalogs: LoadedCatalogs): string {
  const soundsList =
    catalogs.backgroundSounds.length > 0
      ? catalogs.backgroundSounds
          .filter((s) => s.id !== "None")
          .map((s) => s.id)
          .join(", ")
      : "LI, SP, OC, DH, BD";
  const beatsList =
    catalogs.binauralBeats.length > 0
      ? catalogs.binauralBeats.map((b) => b.id).join(", ")
      : "BB2, BB4, BB6, BB10, BB14, BB40";

  let templatesSection = "";
  const templates = guidelines?.session_templates;
  if (templates) {
    const keys = Object.keys(templates).sort((a, b) => {
      const na = parseInt(a.replace(/\D/g, ""), 10) || 0;
      const nb = parseInt(b.replace(/\D/g, ""), 10) || 0;
      return na - nb;
    });
    for (const key of keys) {
      const t = templates[key];
      if (t?.cues) {
        const cueStr = t.cues
          .map((c) => `${c.id}@${c.trigger}`)
          .join(", ");
        templatesSection += `  ${key}: ${cueStr}\n`;
      }
    }
  }

  return `You are a meditation composer. Use the appropriate structure based on duration:

## SHORT SESSIONS (1-6 min)
1 min: SI only + GB | Cues: SI@start, GB@end
2-3 min: SI + ONE relaxation (PB or BS) + GB
4 min: SI + PB + BS + GB (no focus module)
5-6 min: SI + PB + BS + focus (IM2 or NF2) + GB

## LONG SESSIONS (> 6 min) - 4-PHASE
PHASE 1: SI at start
PHASE 2: PB + BS (relaxation)
PHASE 3: IM or NF (focus)
PHASE 4: VC or RT (visualization) - evening=RT, default=VC
CLOSING: GB at end (skip for sleep)

## AVAILABLE
SOUNDS: ${soundsList} | BEATS: ${beatsList}
TRIGGERS: "start", "end", or minute STRING
GB at end for ALL EXCEPT sleep. NEVER repeat trigger cues.

## TEMPLATES
${templatesSection}

Return ONLY valid JSON. Example:
{"duration":5,"backgroundSoundId":"SP","binauralBeatId":"BB10","cues":[{"id":"SI","trigger":"start"},{"id":"PB1","trigger":"1"},{"id":"BS1","trigger":"2"},{"id":"IM2","trigger":"3"},{"id":"GB","trigger":"end"}],"title":"Quick Focus","description":"Light breathwork, body awareness, and I AM mantra with spa background."}`;
}

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

function parseAIResponse(aiResponse: string): AIGeneratedTimer {
  let s = aiResponse.trim();
  if (s.startsWith("```json")) s = s.slice(7);
  if (s.startsWith("```")) s = s.slice(3);
  if (s.endsWith("```")) s = s.slice(0, -3);
  s = s.trim();
  const first = s.indexOf("{");
  const last = s.lastIndexOf("}");
  if (first >= 0 && last > first) s = s.slice(first, last + 1);
  s = s
    .replace(/\uFEFF/g, "")
    .replace(/\u201C/g, '"')
    .replace(/\u201D/g, '"')
    .replace(/\u2018/g, '"')
    .replace(/\u2019/g, '"')
    .replace(/`/g, "");
  s = s.replace(/,\s*}/g, "}");
  s = s.replace(/,\s*]/g, "]");

  const parsed = JSON.parse(s);
  if (!parsed || typeof parsed.duration !== "number" || !Array.isArray(parsed.cues)) {
    throw new Error("Invalid meditation JSON structure");
  }
  return parsed as AIGeneratedTimer;
}

function validate(
  timer: AIGeneratedTimer,
  validCueIds: Set<string>,
  prompt: string
): string | null {
  for (const cue of timer.cues) {
    const valid =
      validCueIds.has(cue.id) ||
      ["SI", "GB"].includes(cue.id) ||
      cue.id.startsWith("PB") ||
      cue.id.startsWith("BS") ||
      cue.id.startsWith("IM") ||
      cue.id.startsWith("NF") ||
      ["OH", "VC", "RT"].includes(cue.id);
    if (!valid) return `Unknown cue: ${cue.id}`;
  }

  const triggerCueIds = new Set(["OH", "VC", "RT"]);
  const used = new Set<string>();
  for (const cue of timer.cues) {
    if (triggerCueIds.has(cue.id)) {
      if (used.has(cue.id)) return `Duplicate trigger cue: ${cue.id}`;
      used.add(cue.id);
    }
  }

  for (const cue of timer.cues) {
    const t = String(cue.trigger).toLowerCase();
    if (t === "start" || t === "end") continue;
    const num = parseInt(t, 10);
    if (isNaN(num) || num < 0 || num >= timer.duration) {
      return `Invalid trigger '${cue.trigger}' for cue ${cue.id}`;
    }
  }

  if (timer.duration < 1) return "Duration must be >= 1";
  if (!timer.backgroundSoundId) return "Background sound required";

  return null;
}

function buildFallback(
  duration: number,
  prompt: string,
  catalogs: LoadedCatalogs
): AIGeneratedTimer {
  const lower = prompt.toLowerCase();
  const isSleep =
    /sleep|bedtime|night|fall asleep|drift off|slumber/.test(lower);
  const isEvening = /evening|wind down|after work|sunset/.test(lower);

  const cues: Array<{ id: string; trigger: string }> = [
    { id: "SI", trigger: "start" },
  ];

  if (duration <= 1) {
    // SI only
  } else if (duration <= 3) {
    cues.push({ id: "PB1", trigger: "1" });
  } else if (duration === 4) {
    cues.push({ id: "PB1", trigger: "1" });
    cues.push({ id: "BS2", trigger: "2" });
  } else if (duration <= 6) {
    cues.push({ id: "PB1", trigger: "1" });
    cues.push({ id: "BS1", trigger: "2" });
    cues.push({ id: "IM2", trigger: "3" });
  } else {
    const pb = Math.min(3, Math.floor(duration * 0.2));
    const bs = Math.min(5, Math.floor(duration * 0.25));
    cues.push({ id: `PB${Math.max(1, pb)}`, trigger: "1" });
    cues.push({ id: `BS${Math.max(1, bs)}`, trigger: String(1 + Math.max(1, pb)) });
    const focusStart = 1 + Math.max(1, pb) + Math.max(1, bs);
    const vizStart = Math.floor(duration * 0.75);
    cues.push({ id: "IM2", trigger: String(focusStart) });
    cues.push({
      id: isEvening ? "RT" : "VC",
      trigger: String(vizStart),
    });
  }

  if (!isSleep) {
    cues.push({ id: "GB", trigger: "end" });
  }

  const bg =
    isSleep ? "OC" : isEvening ? "SP" : "SP";
  const bb = isSleep ? "BB2" : "BB10";

  const soundIds = catalogs.backgroundSounds.map((s) => s.id);
  const beatIds = catalogs.binauralBeats.map((b) => b.id);
  const bgId = soundIds.includes(bg) ? bg : soundIds[0] ?? "SP";
  const bbId = beatIds.includes(bb) ? bb : beatIds[0] ?? "BB10";

  return {
    duration,
    backgroundSoundId: bgId,
    binauralBeatId: bbId,
    cues,
    title: "Custom Meditation",
    description: "A guided meditation tailored to your request.",
  };
}

export interface GenerateAIMeditationInput {
  prompt: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  maxDuration?: number;
  catalogs: LoadedCatalogs;
  apiKey: string;
}

export async function generateAIMeditation(
  input: GenerateAIMeditationInput
): Promise<{ meditation: AIGeneratedTimer; usedFallback: boolean }> {
  const {
    prompt,
    conversationHistory = [],
    maxDuration,
    catalogs,
    apiKey,
  } = input;

  let effectivePrompt = prompt.trim();
  if (maxDuration != null && maxDuration > 0) {
    effectivePrompt = `DURATION CONSTRAINT: This meditation MUST be exactly ${maxDuration} minutes.\n\n${effectivePrompt}`;
  }

  const systemPrompt = buildSystemPrompt(catalogs);
  functions.logger.info(
    `${TAG_AI} postMeditations: openai call started promptLen=${effectivePrompt.length}`
  );

  let rawContent: string;
  try {
    rawContent = await callOpenAI(
      effectivePrompt,
      systemPrompt,
      conversationHistory,
      apiKey
    );
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    functions.logger.warn(
      `${TAG_AI} postMeditations: openai call failed - ${errMsg}, using fallback`
    );
    const duration = maxDuration ?? 10;
    const meditation = buildFallback(duration, prompt, catalogs);
    return { meditation, usedFallback: true };
  }

  let meditation: AIGeneratedTimer;
  let usedFallback = false;

  try {
    meditation = parseAIResponse(rawContent);
    functions.logger.info(
      `${TAG_AI} postMeditations: parse result success dur=${meditation.duration} cues=${meditation.cues.length}`
    );
  } catch {
    functions.logger.warn(
      `${TAG_AI} postMeditations: parse failed, using fallback`
    );
    meditation = buildFallback(maxDuration ?? 10, prompt, catalogs);
    usedFallback = true;
  }

  const validCueIds = new Set(catalogs.cues.map((c) => c.id));
  const validationError = validate(meditation, validCueIds, prompt);
  if (validationError) {
    functions.logger.warn(
      `${TAG_AI} postMeditations: validation failed - ${validationError}, using fallback`
    );
    meditation = buildFallback(meditation.duration, prompt, catalogs);
    usedFallback = true;
  }

  return { meditation, usedFallback };
}
