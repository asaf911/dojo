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
      ? catalogs.binauralBeats.map((b) => b.id).join(", ")
      : "BB2, BB4, BB6, BB10, BB14, BB40";

  const systemPrompt = `You generate meditation metadata only. The structure is already fixed.

Given this meditation structure: ${structureContext}
Duration: ${duration} min. User said: "${userPrompt}"

Return JSON only with these exact keys:
{ "title": "short title", "description": "brief description", "binauralBeatId": "ID" }

AVAILABLE BEATS: ${beatsList}
Select the binaural beat that best fits the session type (sleep, focus, relaxation, etc.). Use valid IDs from the list.`;

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
  catalogs: LoadedCatalogs
): { title: string; description: string; backgroundSoundId: string; binauralBeatId: string } {
  const soundIds = catalogs.backgroundSounds.map((s) => s.id);
  const beatIds = catalogs.binauralBeats.map((b) => b.id);
  const bgId =
    pickRandomFromCatalog(catalogs.backgroundSounds, "None")?.id ??
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
        pickRandomFromCatalog(catalogs.backgroundSounds, "None")?.id ??
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
    metadata = buildFallbackMetadata(duration, prefs, catalogs);
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
