/**
 * AI meditation generation: deterministic structure + AI metadata only.
 * Structure is computed by phaseAllocation + cueBuilder (no automatic Gentle Bell; GB only if product adds it elsewhere).
 * AI provides title, description, sounds.
 */

import * as functions from "firebase-functions";
import {
  allocatePhases,
  allocatePhasesFromOverrides,
  extractDurationFromConversationHistory,
  extractDurationFromPrompt,
  extractSessionPreferences,
  minFocusMinutesForVisualizationFocus,
  rebalanceAllocationForMinimumFocus,
  type UserStructureOverrides,
} from "./phaseAllocation";
import { buildCuesFromAllocation } from "./cueBuilder";
import {
  type FractionalCompositionContext,
  normalizeThemeList,
  resolveEveningVisualizationVariant,
  resolveMorningVisualizationVariant,
  resolveMeditationThemes,
  themeCompositionHints,
} from "./meditationThemes";
import {
  pickBackgroundSoundForBlueprint,
  pickBinauralBeatForBlueprint,
  resolveBlueprintFromContext,
  getBlueprintCueHintMerge,
  vizChosenForBlueprintTerminal,
  type MeditationBlueprint,
} from "./meditationBlueprints";
import { pickDisplayTitle } from "./aiMeditationDisplayTitle";

export interface AIGeneratedTimer {
  duration: number;
  backgroundSoundId: string;
  binauralBeatId?: string | null;
  cues: Array<{ id: string; trigger: string; durationMinutes?: number }>;
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

/** AI-extracted structure requirements. User requests take highest priority. */
interface AIStructureRequirements {
  totalDuration?: number;
  mantraMinutes?: number;
  bodyScanMinutes?: number;
  breathMinutes?: number;
  focusType?: "IM" | "NF";
  /** Body scan direction when user specifies (head-to-toe vs feet-to-head). */
  bodyScanDirection?: "up" | "down";
  /** Subset of canonical theme ids: morning, evening, noon, night, sleep, gratitude */
  themes?: string[];
  /** Explicit morning visualization module (when wording is indirect). */
  wantsMorningVisualization?: "key_moments" | "gratitude";
  /** Explicit evening visualization module (retrospection vs gratitude). */
  wantsEveningVisualization?: "key_moments" | "gratitude";
}

async function extractUserStructureRequirements(
  userPrompt: string,
  conversationHistory: Array<{ role: string; content: string }>,
  apiKey: string
): Promise<AIStructureRequirements | null> {
  const systemPrompt = `You extract meditation structure requirements from the user's message.
The user may specify: total duration (e.g. "3m", "10 min"), mantra duration ("2m mantra", "3 min mantra"), body scan duration ("2m body scan"), breath duration ("1m breath"), focus type.

Keys: totalDuration (int), mantraMinutes (int), bodyScanMinutes (int), breathMinutes (int), focusType ("IM" or "NF"), bodyScanDirection ("up" or "down"), themes (array of strings, optional), wantsMorningVisualization (optional string), wantsEveningVisualization (optional string).

themes: optional array, each value one of: morning, evening, noon, night, sleep, gratitude. Set when the user clearly wants that theme (e.g. "morning gratitude" → ["gratitude","morning"] or ["morning","gratitude"]).

wantsMorningVisualization: set when the user clearly wants the guided morning visualization module even if they omit the word "visualization": "key_moments" or "gratitude". Use with short sessions so structure can reserve focus time for MV.
wantsEveningVisualization: same for evening rewind/gratitude visualization ("key_moments" = retrospection, "gratitude" = evening gratitude). Never set both wantsMorningVisualization and wantsEveningVisualization; pick one from context.
- focusType "IM" = mantra, chant, affirmation, I AM
- focusType "NF" = nostril, nostril focus, nostril breathing, alternate nostril, nasal focus, breath focus on nose
IMPORTANT: If the user mentions nostril, nose, or nasal breathing/focus, ALWAYS set focusType to "NF".
- bodyScanDirection "down" = head to toe, top to bottom, crown to feet, start at head (matches cue BS_FRAC_DOWN)
- bodyScanDirection "up" = feet to head, bottom to top, toes to crown, start at feet (matches cue BS_FRAC_UP)
- If the user says "remove mantra", "no mantra", "without mantra", or "skip mantra": do NOT set mantraMinutes to 0; omit mantraMinutes entirely unless they give a positive mantra duration. Prefer themes like gratitude/morning and wantsMorningVisualization when they ask for gratitude visualization instead.

Return JSON only with keys you can infer. Use null for unspecified.

Examples:
- "Make a 3m relaxation. 2m mantra" → {"totalDuration":3,"mantraMinutes":2,"focusType":"IM"}
- "5 min with 2m body scan" → {"totalDuration":5,"bodyScanMinutes":2}
- "8 min body scan from head to toe" → {"totalDuration":8,"bodyScanMinutes":5,"bodyScanDirection":"down"}
- "relaxation scan starting at my feet" → {"bodyScanDirection":"up"}
- "10m meditation, 3 minutes mantra" → {"totalDuration":10,"mantraMinutes":3,"focusType":"IM"}
- "10 minute nostril focus meditation" → {"totalDuration":10,"focusType":"NF"}
- "5 min nostril breathing" → {"totalDuration":5,"focusType":"NF"}
- "just a quick 2 min" → {"totalDuration":2}
- "5m" → {"totalDuration":5}
- "4 min morning visualization" → {"totalDuration":4,"themes":["morning"],"wantsMorningVisualization":"key_moments"}
- "ultra short gratitude visualization" → {"themes":["gratitude"],"wantsMorningVisualization":"gratitude"}
- "Remove mantra, add morning gratitude" → {"themes":["morning","gratitude"],"wantsMorningVisualization":"gratitude"}
- "No mantra, 5 min morning gratitude" → {"totalDuration":5,"themes":["morning","gratitude"],"wantsMorningVisualization":"gratitude"}

Return ONLY valid JSON. No other text.`;

  const messages: Array<{ role: string; content: string }> = [
    { role: "system", content: systemPrompt },
    ...conversationHistory,
    { role: "user", content: userPrompt },
  ];

  try {
    const response = await fetch("https://api.openai.com/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${apiKey}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model: "gpt-4o-mini",
        messages,
        max_tokens: 150,
        temperature: 0.3,
      }),
    });

    const body = await response.text();
    if (!response.ok) {
      functions.logger.warn(`${TAG_AI} extractStructure API error status=${response.status}`);
      return null;
    }

    const parsed = JSON.parse(body);
    const content = parsed?.choices?.[0]?.message?.content;
    if (!content || typeof content !== "string") {
      functions.logger.warn(`${TAG_AI} extractStructure no content`);
      return null;
    }

    let s = content.trim();
    if (s.startsWith("```json")) s = s.slice(7);
    if (s.startsWith("```")) s = s.slice(3);
    if (s.endsWith("```")) s = s.slice(0, -3);
    s = s.trim();
    const first = s.indexOf("{");
    const last = s.lastIndexOf("}");
    if (first >= 0 && last > first) s = s.slice(first, last + 1);
    s = s.replace(/,\s*}/g, "}");
    s = s.replace(/,\s*]/g, "]");

    const raw = JSON.parse(s) as AIStructureRequirements & { themes?: unknown };
    const bodyScanDirection =
      raw.bodyScanDirection === "up" || raw.bodyScanDirection === "down"
        ? raw.bodyScanDirection
        : undefined;
    const llmThemes = normalizeThemeList(raw.themes);
    const wm = raw.wantsMorningVisualization;
    const wantsMorningVisualization =
      wm === "gratitude" || wm === "key_moments" ? wm : undefined;
    const we = (raw as { wantsEveningVisualization?: unknown }).wantsEveningVisualization;
    const wantsEveningVisualization =
      we === "gratitude" || we === "key_moments" ? we : undefined;
    const result: AIStructureRequirements = {
      ...raw,
      bodyScanDirection,
      themes: llmThemes.length > 0 ? llmThemes : undefined,
      wantsMorningVisualization,
      wantsEveningVisualization,
    };
    if (
      result.mantraMinutes === 0 &&
      result.focusType !== "IM"
    ) {
      result.mantraMinutes = undefined;
    }
    functions.logger.info(`${TAG_AI} extractStructure raw=${JSON.stringify(result)}`);
    const hasOverride =
      result.mantraMinutes != null ||
      result.bodyScanMinutes != null ||
      result.breathMinutes != null ||
      result.focusType != null ||
      bodyScanDirection != null ||
      wantsMorningVisualization != null ||
      wantsEveningVisualization != null;
    const hasThemes = llmThemes.length > 0;
    return hasOverride || hasThemes ? result : null;
  } catch (e) {
    functions.logger.warn(`${TAG_AI} extractStructure error: ${e}`);
    return null;
  }
}

async function callOpenAIMetadata(
  userPrompt: string,
  structureContext: string,
  duration: number,
  conversationHistory: Array<{ role: string; content: string }>,
  catalogs: LoadedCatalogs,
  apiKey: string,
  lockedTitle: string
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

  const titleJson = JSON.stringify(lockedTitle);
  const systemPrompt = `You generate meditation metadata only. The structure is already fixed.

Given this meditation structure: ${structureContext}
Duration: ${duration} min. User said: "${userPrompt}"

The app display title is fixed — use it verbatim for the JSON "title" field (same spelling and spacing): ${titleJson}
Do not invent a different title. Put your creativity into "description" only (one brief sentence that fits the user's request).

Return JSON only with these exact keys:
{ "title": ${titleJson}, "description": "brief description", "binauralBeatId": "ID" }

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
  recentBackgroundSounds: string[] | undefined,
  displayTitle: string,
  blueprint: MeditationBlueprint | null
): { title: string; description: string; backgroundSoundId: string; binauralBeatId: string } {
  const soundIds = catalogs.backgroundSounds.map((s) => s.id);
  const beatIds = catalogs.binauralBeats.map((b) => b.id);
  const bgPick = blueprint
    ? pickBackgroundSoundForBlueprint(
        catalogs.backgroundSounds,
        "None",
        blueprint.audioHints.backgroundSound,
        recentBackgroundSounds
      )
    : pickWeightedRandomFromCatalog(
        catalogs.backgroundSounds,
        "None",
        recentBackgroundSounds
      );
  const bgId =
    bgPick?.id ??
    soundIds.find((id) => id !== "None") ??
    "SP";
  const bbPick = blueprint
    ? pickBinauralBeatForBlueprint(
        catalogs.binauralBeats,
        blueprint.audioHints.binauralBeat
      )
    : pickRandomFromCatalog(catalogs.binauralBeats);
  const bbId = bbPick?.id ?? beatIds[0] ?? "BB10";
  return {
    title: displayTitle,
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
  /** iOS Explore context.displayName — merged into theme resolution on the server */
  exploreTimeOfDay?: string | null;
  /** Explicit theme tags from the client (canonical ids) */
  clientMeditationThemes?: string[];
  /** Optional product blueprint id (e.g. timely.morning); server resolves structure + audio bias */
  clientBlueprintId?: string | null;
}

export type { FractionalCompositionContext } from "./meditationThemes";

export async function generateAIMeditation(
  input: GenerateAIMeditationInput
): Promise<{
  meditation: AIGeneratedTimer;
  usedFallback: boolean;
  fractionalCompositionContext: FractionalCompositionContext;
}> {
  const {
    prompt,
    conversationHistory = [],
    maxDuration,
    lastMeditationDuration,
    catalogs,
    apiKey,
    recentBackgroundSounds,
    exploreTimeOfDay,
    clientMeditationThemes,
    clientBlueprintId,
  } = input;

  let duration =
    maxDuration ??
    extractDurationFromPrompt(prompt) ??
    lastMeditationDuration ??
    extractDurationFromConversationHistory(conversationHistory) ??
    10;

  const prefs = extractSessionPreferences(prompt);

  // AI extracts user-explicit requirements (e.g. "2m mantra") — highest priority
  const userOverrides = await extractUserStructureRequirements(
    prompt.trim(),
    conversationHistory,
    apiKey
  );

  if (userOverrides?.totalDuration != null && userOverrides.totalDuration >= 1 && userOverrides.totalDuration <= 60) {
    duration = userOverrides.totalDuration;
  }

  const overrides: UserStructureOverrides = {
    totalDuration: duration,
    mantraMinutes: userOverrides?.mantraMinutes,
    bodyScanMinutes: userOverrides?.bodyScanMinutes,
    breathMinutes: userOverrides?.breathMinutes,
    focusType: userOverrides?.focusType,
  };

  const hasExplicitOverrides =
    overrides.mantraMinutes != null ||
    overrides.bodyScanMinutes != null ||
    overrides.breathMinutes != null ||
    overrides.focusType != null;

  let allocation = hasExplicitOverrides
    ? allocatePhasesFromOverrides(duration, overrides, prefs)
    : allocatePhases(duration, prefs);

  const llmThemeTags = normalizeThemeList(userOverrides?.themes);
  const themes = resolveMeditationThemes({
    prompt,
    conversationHistory,
    clientThemes: clientMeditationThemes ?? [],
    llmThemes: llmThemeTags,
    exploreTimeOfDay: exploreTimeOfDay ?? null,
    prefs,
  });

  const blueprint = resolveBlueprintFromContext({
    clientBlueprintId: clientBlueprintId ?? null,
    themes,
    prefs,
  });

  const evVariant = resolveEveningVisualizationVariant({
    prompt,
    llmWants: userOverrides?.wantsEveningVisualization ?? null,
    mergedThemes: themes,
    prefs,
  });
  const mvVariant = resolveMorningVisualizationVariant({
    prompt,
    llmWants: userOverrides?.wantsMorningVisualization ?? null,
    mergedThemes: themes,
  });

  type VizChosen = "MV_KM" | "MV_GR" | "EV_KM" | "EV_GR";
  let vizChosen: VizChosen | null = null;
  if (userOverrides?.wantsEveningVisualization != null) {
    vizChosen =
      userOverrides.wantsEveningVisualization === "gratitude" ? "EV_GR" : "EV_KM";
  } else if (userOverrides?.wantsMorningVisualization != null) {
    vizChosen =
      userOverrides.wantsMorningVisualization === "gratitude" ? "MV_GR" : "MV_KM";
  } else if (blueprint) {
    vizChosen = vizChosenForBlueprintTerminal(blueprint, themes);
  }

  if (vizChosen == null) {
    if (evVariant != null && mvVariant == null) {
      vizChosen = evVariant === "EV_GR" ? "EV_GR" : "EV_KM";
    } else if (mvVariant != null && evVariant == null) {
      vizChosen = mvVariant === "MV_GR" ? "MV_GR" : "MV_KM";
    } else if (evVariant != null && mvVariant != null) {
      vizChosen = evVariant === "EV_GR" ? "EV_GR" : "EV_KM";
      functions.logger.info(
        `${TAG_AI} vizArb ev=${evVariant} mv=${mvVariant} -> ${vizChosen}`
      );
    }
  }

  const userPinnedModuleMinutes =
    overrides.mantraMinutes != null ||
    overrides.bodyScanMinutes != null ||
    overrides.breathMinutes != null;

  const isNightDual = blueprint?.terminalMode === "NIGHT_IM_THEN_EV";

  if (
    isNightDual &&
    !userPinnedModuleMinutes &&
    overrides.focusType !== "IM" &&
    overrides.focusType !== "NF"
  ) {
    const minEv = Math.max(
      2,
      minFocusMinutesForVisualizationFocus(duration, prompt)
    );
    const minIm = 1;
    allocation = rebalanceAllocationForMinimumFocus(
      allocation,
      duration,
      minEv + minIm
    );
    functions.logger.info(
      `${TAG_AI} night_dual rebalance minIm=${minIm} minEv=${minEv} focus=${allocation.focus}`
    );
  }

  const shouldReserveVisualizationViz =
    vizChosen != null &&
    !prefs.isSleep &&
    overrides.focusType !== "IM" &&
    overrides.focusType !== "NF" &&
    !userPinnedModuleMinutes &&
    !isNightDual;

  if (shouldReserveVisualizationViz) {
    const minFocus = minFocusMinutesForVisualizationFocus(duration, prompt);
    allocation = rebalanceAllocationForMinimumFocus(
      allocation,
      duration,
      minFocus
    );
    functions.logger.info(
      `${TAG_AI} visualization vizChosen=${vizChosen} minFocus=${minFocus} breath=${allocation.breath} relax=${allocation.relax} focus=${allocation.focus} insight=${allocation.insight}`
    );
  }

  const themeHintOptions =
    isNightDual
      ? undefined
      : vizChosen != null && allocation.focus > 0
        ? {
            forcedFocusFractionalId:
              vizChosen === "EV_GR"
                ? ("EV_GR_FRAC" as const)
                : vizChosen === "EV_KM"
                  ? ("EV_KM_FRAC" as const)
                  : vizChosen === "MV_GR"
                    ? ("MV_GR_FRAC" as const)
                    : ("MV_KM_FRAC" as const),
          }
        : undefined;

  let { fractionalContext: fractionalCompositionContext, cueHints } =
    themeCompositionHints(
      themes,
      prefs,
      overrides,
      allocation.focus,
      themeHintOptions
    );

  const userChoseImNf =
    overrides.focusType === "IM" || overrides.focusType === "NF";
  if (blueprint && !userChoseImNf) {
    const patch = getBlueprintCueHintMerge({
      blueprint,
      themes,
      prefs,
      focusMinutes: allocation.focus,
      userChoseImNf: false,
    });
    if (patch) {
      if (patch.cueHints.secondFocusFractionalId) {
        delete cueHints.focusFractionalId;
      }
      Object.assign(fractionalCompositionContext, patch.fractionalContext);
      Object.assign(cueHints, patch.cueHints);
    }
  }

  const bodyScanDirectionForCue =
    userOverrides?.bodyScanDirection === "up" ||
    userOverrides?.bodyScanDirection === "down"
      ? userOverrides.bodyScanDirection
      : undefined;

  const cues = buildCuesFromAllocation(allocation, prefs, {
    bodyScanDirection: bodyScanDirectionForCue,
    practiceDurationMinutes: duration,
    themeCueHints: cueHints,
  });

  const structureContext = cues.map((c) => `${c.id}@${c.trigger}`).join(", ");
  functions.logger.info(
    `${TAG_AI} structure dur=${duration} cues=${cues.length} userOverrides=${hasExplicitOverrides ? JSON.stringify(overrides) : "none"}`
  );

  const mvVariantForTitle =
    vizChosen === "MV_KM" || vizChosen === "MV_GR"
      ? vizChosen === "MV_GR"
        ? ("MV_GR" as const)
        : ("MV_KM" as const)
      : null;
  const evVariantForTitle =
    vizChosen === "EV_KM" || vizChosen === "EV_GR"
      ? vizChosen === "EV_GR"
        ? ("EV_GR" as const)
        : ("EV_KM" as const)
      : null;

  const { title: displayTitle, bucket: displayTitleBucket } = pickDisplayTitle({
    prompt: prompt.trim(),
    duration,
    themes,
    prefs,
    mvVariant: mvVariantForTitle,
    evVariant: evVariantForTitle,
    overrides,
    structureContext,
  });
  functions.logger.info(
    `${TAG_AI} displayTitle bucket=${displayTitleBucket} title=${JSON.stringify(displayTitle)}`
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
      apiKey,
      displayTitle
    );
    const beatIds = catalogs.binauralBeats.map((b) => b.id);
    const soundIds = catalogs.backgroundSounds.map((s) => s.id);
    const bgPick = blueprint
      ? pickBackgroundSoundForBlueprint(
          catalogs.backgroundSounds,
          "None",
          blueprint.audioHints.backgroundSound,
          recentBackgroundSounds
        )
      : pickWeightedRandomFromCatalog(
          catalogs.backgroundSounds,
          "None",
          recentBackgroundSounds
        );
    const bbFromBlueprint = blueprint
      ? pickBinauralBeatForBlueprint(
          catalogs.binauralBeats,
          blueprint.audioHints.binauralBeat
        )
      : undefined;
    metadata = {
      title: displayTitle,
      description: ai.description?.trim() || "A guided meditation tailored to your request.",
      backgroundSoundId:
        bgPick?.id ??
        soundIds.find((id) => id !== "None") ??
        "SP",
      binauralBeatId:
        (bbFromBlueprint?.id && beatIds.includes(bbFromBlueprint.id)
          ? bbFromBlueprint.id
          : undefined) ??
        (ai.binauralBeatId && beatIds.includes(ai.binauralBeatId)
          ? ai.binauralBeatId
          : pickRandomFromCatalog(catalogs.binauralBeats)?.id) ??
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
      recentBackgroundSounds,
      displayTitle,
      blueprint
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

  return { meditation, usedFallback, fractionalCompositionContext };
}
