/**
 * AI meditation generation: deterministic structure + AI metadata only.
 * Structure is computed by phaseAllocation + cueBuilder; AI provides title, description, sounds.
 */

import * as functions from "firebase-functions";
import {
  allocatePhases,
  extractDurationFromConversationHistory,
  extractDurationFromPrompt,
  extractSessionPreferences,
} from "./phaseAllocation";
import { buildCuesFromAllocation } from "./cueBuilder";

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
  cues: Array<{ id: string; name: string; url: string; urlsByVoice?: Record<string, string> }>;
  bodyScanDurations: Record<string, number>;
}

const TAG_AI = "[Server][Meditations-AI]";

function pickRandomFromCatalog<T extends { id?: string }>(
  items: T[],
  excludeId?: string
): T | undefined {
  const filtered = excludeId
    ? items.filter((item) => item.id !== excludeId)
    : items;
  if (filtered.length === 0) return undefined;
  return filtered[Math.floor(Math.random() * filtered.length)];
}

/** Weighted random: recently used items get lower weight (recentWeight) to reduce repetition */
function pickWeightedRandomFromCatalog<T extends { id?: string }>(
  items: T[],
  excludeId?: string,
  recentlyUsedIds?: string[],
  recentWeight = 0.3
): T | undefined {
  const filtered = excludeId
    ? items.filter((item) => item.id !== excludeId)
    : items;
  if (filtered.length === 0) return undefined;
  const recentSet = new Set(recentlyUsedIds ?? []);
  const weights = filtered.map((item) =>
    item.id && recentSet.has(item.id) ? recentWeight : 1.0
  );
  const total = weights.reduce((a, b) => a + b, 0);
  if (total <= 0) return filtered[Math.floor(Math.random() * filtered.length)];
  let r = Math.random() * total;
  for (let i = 0; i < filtered.length; i++) {
    r -= weights[i];
    if (r <= 0) return filtered[i];
  }
  return filtered[filtered.length - 1];
}

interface AIMetadataResponse {
  title?: string;
  description?: string;
  backgroundSoundId?: string;
  binauralBeatId?: string;
}

async function callOpenAIMetadata(
  userPrompt: string,
  structureContext: string,
  duration: number,
  conversationHistory: Array<{ role: string; content: string }>,
  catalogs: LoadedCatalogs,
  apiKey: string
): Promise<AIMetadataResponse> {
  const beatsList =
    catalogs.binauralBeats.length > 0
      ? catalogs.binauralBeats
          .map((b) => {
            const category = b.name.match(/\(([^)]+)\)/)?.[1] ?? b.id;
            return `${b.id} (${category})`;
          })
          .join(", ")
      : "BB2 (Sleep), BB4 (Imagination), BB6 (Vision), BB10 (Relaxation), BB14 (Focus), BB40 (Gratitude)";

  const systemPrompt = `You generate meditation metadata only. The structure is already fixed.

Given this meditation structure: ${structureContext}
Duration: ${duration} min. User said: "${userPrompt}"

Return JSON only with these exact keys:
{ "title": "short title", "description": "brief description", "binauralBeatId": "ID" }

BINAURAL BEATS (each has a purpose - match user intent to the closest beat):
${beatsList}

Examples: gratitude -> BB40, focus -> BB14, sleep -> BB2, relaxation -> BB10, imagination/creativity -> BB4, vision/intention -> BB6.
Select the beat that best matches what the user asked for. Use valid IDs only.`;

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
      max_tokens: 200,
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

  let s = content.trim();
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

  return JSON.parse(s) as AIMetadataResponse;
}

function buildFallbackMetadata(
  duration: number,
  prefs: { isSleep: boolean; isEvening: boolean },
  catalogs: LoadedCatalogs,
  recentBackgroundSounds?: string[]
): { title: string; description: string; backgroundSoundId: string; binauralBeatId: string } {
  const soundIds = catalogs.backgroundSounds.map((s) => s.id);
  const beatIds = catalogs.binauralBeats.map((b) => b.id);
  const bgId =
    pickWeightedRandomFromCatalog(
      catalogs.backgroundSounds,
      "None",
      recentBackgroundSounds
    )?.id ??
    soundIds.find((id) => id !== "None") ??
    "SP";
  const bbId =
    pickRandomFromCatalog(catalogs.binauralBeats)?.id ?? beatIds[0] ?? "BB10";
  return {
    title: "Custom Meditation",
    description: "A guided meditation tailored to your request.",
    backgroundSoundId: bgId,
    binauralBeatId: bbId,
  };
}

export interface GenerateAIMeditationInput {
  prompt: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  maxDuration?: number;
  lastMeditationDuration?: number;
  catalogs: LoadedCatalogs;
  apiKey: string;
  /** Last N background sound IDs used; down-weighted for variety */
  recentBackgroundSounds?: string[];
}

export async function generateAIMeditation(
  input: GenerateAIMeditationInput
): Promise<{ meditation: AIGeneratedTimer; usedFallback: boolean }> {
  const {
    prompt,
    conversationHistory = [],
    maxDuration,
    lastMeditationDuration,
    catalogs,
    apiKey,
    recentBackgroundSounds,
  } = input;

  const duration =
    maxDuration ??
    extractDurationFromPrompt(prompt) ??
    lastMeditationDuration ??
    extractDurationFromConversationHistory(conversationHistory) ??
    10;
  const prefs = extractSessionPreferences(prompt);
  const allocation = allocatePhases(duration, prefs);
  const cues = buildCuesFromAllocation(allocation, prefs);

  const structureContext = cues.map((c) => `${c.id}@${c.trigger}`).join(", ");
  functions.logger.info(
    `${TAG_AI} deterministic structure dur=${duration} cues=${cues.length}`
  );

  let metadata: {
    title: string;
    description: string;
    backgroundSoundId: string;
    binauralBeatId: string;
  };
  let usedFallback = false;

  try {
    const ai = await callOpenAIMetadata(
      prompt.trim(),
      structureContext,
      duration,
      conversationHistory,
      catalogs,
      apiKey
    );
    const beatIds = catalogs.binauralBeats.map((b) => b.id);
    const soundIds = catalogs.backgroundSounds.map((s) => s.id);
    metadata = {
      title: ai.title?.trim() || "Custom Meditation",
      description: ai.description?.trim() || "A guided meditation tailored to your request.",
      backgroundSoundId:
        pickWeightedRandomFromCatalog(
          catalogs.backgroundSounds,
          "None",
          recentBackgroundSounds
        )?.id ??
        soundIds.find((id) => id !== "None") ??
        "SP",
      binauralBeatId:
        ai.binauralBeatId && beatIds.includes(ai.binauralBeatId)
          ? ai.binauralBeatId
          : pickRandomFromCatalog(catalogs.binauralBeats)?.id ??
            beatIds[0] ??
            "BB10",
    };
  } catch (err) {
    const errMsg = err instanceof Error ? err.message : String(err);
    functions.logger.warn(
      `${TAG_AI} AI metadata call failed - ${errMsg}, using fallback`
    );
    metadata = buildFallbackMetadata(
      duration,
      prefs,
      catalogs,
      recentBackgroundSounds
    );
    usedFallback = true;
  }

  const meditation: AIGeneratedTimer = {
    duration,
    backgroundSoundId: metadata.backgroundSoundId,
    binauralBeatId: metadata.binauralBeatId,
    cues,
    title: metadata.title,
    description: metadata.description,
  };

  return { meditation, usedFallback };
}
