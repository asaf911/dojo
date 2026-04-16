/**
 * Canonical meditation themes for AI composition: merge prompt, client context, LLM, and SessionPreferences.
 * Drives INT_FRAC greeting family, focus fractional (MV / EV vs IM/NF), and insight cue.
 */

import type {
  SessionPreferences,
  UserStructureOverrides,
} from "./phaseAllocation";
import { promptIndicatesSleepPracticeIntent } from "./phaseAllocation";

export const MEDITATION_THEME_IDS = [
  "morning",
  "evening",
  "noon",
  "night",
  "sleep",
  "gratitude",
] as const;

export type MeditationThemeId = (typeof MEDITATION_THEME_IDS)[number];

function eveningOnlyWithoutMorning(mergedThemes: MeditationThemeId[]): boolean {
  const eveningish =
    mergedThemes.includes("evening") || mergedThemes.includes("night");
  return eveningish && !mergedThemes.includes("morning");
}

/** Carried through expandFractionalCues → composeIntroFractionalPlan(INT_FRAC). */
export type FractionalCompositionContext = {
  greetingFamilyHint?: "morning" | "evening" | "neutral" | "returning";
};

/** Hints for cueBuilder (focus row). */
export type ThemeCompositionHints = {
  focusFractionalId?:
    | "IM_FRAC"
    | "NF_FRAC"
    | "MV_KM_FRAC"
    | "MV_GR_FRAC"
    | "EV_KM_FRAC"
    | "EV_GR_FRAC";
  /** Second focus row (e.g. night: IM then evening visualization). Requires `focus >= 2`. */
  secondFocusFractionalId?: "EV_KM_FRAC" | "EV_GR_FRAC";
};

function isMeditationThemeId(s: string): s is MeditationThemeId {
  return (MEDITATION_THEME_IDS as readonly string[]).includes(s as MeditationThemeId);
}

/** Normalize arbitrary strings (LLM / client) to canonical theme ids. */
export function normalizeThemeList(raw: unknown): MeditationThemeId[] {
  if (!Array.isArray(raw)) return [];
  const out: MeditationThemeId[] = [];
  for (const x of raw) {
    const n = String(x).trim().toLowerCase();
    if (isMeditationThemeId(n)) out.push(n);
  }
  return out;
}

/**
 * Keyword pass on one text blob (prompt or history message).
 * "Night" as time-of-day is separate from sleep (see SessionPreferences.isSleep refinement).
 */
export function extractThemesFromText(text: string): MeditationThemeId[] {
  const lower = text.toLowerCase();
  const found = new Set<MeditationThemeId>();

  if (/morning|moning|wake up|start (my |the )?day|sunrise|energize/.test(lower)) {
    found.add("morning");
  }
  if (/evening|wind down|after work|sunset|end of day/.test(lower)) {
    found.add("evening");
  }
  if (/\bnoon\b|midday|mid-day|lunch break/.test(lower)) {
    found.add("noon");
  }
  if (
    /\b(at night|tonight|nighttime|late night)\b/.test(lower) ||
    (/\bnight\b/.test(lower) &&
      !/sleep|asleep|bedtime|fall asleep|nap|insomnia|good night/.test(lower))
  ) {
    found.add("night");
  }
  if (promptIndicatesSleepPracticeIntent(lower)) {
    found.add("sleep");
  }
  if (/gratitude|grateful|thankful/.test(lower)) {
    found.add("gratitude");
  }

  return [...found];
}

/** Prompt + recent user turns only (no assistant / no prefs) for precedence over ambient context. */
function explicitUserThemesForSleepPrecedence(args: {
  prompt: string;
  conversationHistory?: Array<{ role: string; content: string }>;
}): Set<MeditationThemeId> {
  const out = new Set<MeditationThemeId>();
  for (const t of extractThemesFromText(args.prompt)) out.add(t);
  const hist = args.conversationHistory ?? [];
  for (const m of hist.slice(-3)) {
    if (m.role === "user") {
      for (const t of extractThemesFromText(m.content)) out.add(t);
    }
  }
  return out;
}

/**
 * Wall-clock / explore inject `sleep` while the user may ask for morning practice.
 * If the user explicitly asked for morning and did not ask for sleep, drop ambient sleep.
 */
function stripAmbientSleepWhenMorningExplicit(
  set: Set<MeditationThemeId>,
  args: {
    prompt: string;
    conversationHistory?: Array<{ role: string; content: string }>;
  }
): void {
  const explicit = explicitUserThemesForSleepPrecedence(args);
  if (explicit.has("morning") && !explicit.has("sleep")) {
    set.delete("sleep");
  }
}

const THEME_PRIORITY: MeditationThemeId[] = [
  "sleep",
  "gratitude",
  "morning",
  "evening",
  "noon",
  "night",
];

/** Maps Explore `timeOfDay` display strings (see iOS ExploreRecommendationManager) to canonical themes. */
export function themesFromExploreTimeOfDay(
  name: string | null | undefined
): MeditationThemeId[] {
  if (!name) return [];
  const n = name.trim().toLowerCase();
  if (n === "morning") return ["morning"];
  if (n === "midday") return ["noon"];
  if (n === "evening") return ["evening"];
  if (n === "night") return ["sleep"];
  return [];
}

export function resolveMeditationThemes(args: {
  prompt: string;
  conversationHistory?: Array<{ role: string; content: string }>;
  clientThemes?: string[];
  llmThemes?: string[];
  exploreTimeOfDay?: string | null;
  prefs: SessionPreferences;
}): MeditationThemeId[] {
  const set = new Set<MeditationThemeId>();

  for (const t of extractThemesFromText(args.prompt)) set.add(t);
  const hist = args.conversationHistory ?? [];
  for (const m of hist.slice(-3)) {
    for (const t of extractThemesFromText(m.content)) set.add(t);
  }

  if (args.prefs.isMorning) set.add("morning");
  if (args.prefs.isEvening) set.add("evening");
  if (args.prefs.isSleep) set.add("sleep");

  for (const t of themesFromExploreTimeOfDay(args.exploreTimeOfDay)) set.add(t);
  for (const t of normalizeThemeList(args.clientThemes)) set.add(t);
  for (const t of normalizeThemeList(args.llmThemes)) set.add(t);

  stripAmbientSleepWhenMorningExplicit(set, {
    prompt: args.prompt,
    conversationHistory: args.conversationHistory,
  });

  return THEME_PRIORITY.filter((t) => set.has(t));
}

export type MorningVisualizationVariant = "MV_KM" | "MV_GR";

/**
 * Detects explicit morning / gratitude visualization intent so we can reserve focus minutes
 * and pick MV_KM vs MV_GR even when default phase tables leave focus at 0.
 */
export function resolveMorningVisualizationVariant(args: {
  prompt: string;
  llmWants?: "key_moments" | "gratitude" | null;
  mergedThemes: MeditationThemeId[];
}): MorningVisualizationVariant | null {
  if (args.llmWants === "gratitude") return "MV_GR";
  if (args.llmWants === "key_moments") return "MV_KM";

  const lower = args.prompt.toLowerCase();
  const gratitudeTheme = args.mergedThemes.includes("gratitude");
  const morningTheme =
    args.mergedThemes.includes("morning") ||
    /morning|moning|\bmorn\b|wake\s+up|start\s+(my\s+|the\s+)?day|sunrise/.test(
      lower
    );

  if (/gratitude|grateful|thankful/.test(lower) || gratitudeTheme) {
    if (eveningOnlyWithoutMorning(args.mergedThemes)) return null;
    return "MV_GR";
  }
  // Morning (slot or copy): always reserve morning visualization — do not require
  // the word "visualize" (product blueprints describe "Morning visualization" as a segment label).
  if (morningTheme && !eveningOnlyWithoutMorning(args.mergedThemes)) {
    return "MV_KM";
  }

  const vizCue =
    /\bvisuali[sz]ations?\b|\bvisuali[sz]e\b|\bimagin(e|ing)\b|\benvision\b|\bkey\s+moments?\b|\bguided\s+imagery\b/.test(
      lower
    );
  if (!vizCue) return null;

  return null;
}

export type EveningVisualizationVariant = "EV_KM" | "EV_GR";

function eveningVisualizationEveningishContext(args: {
  mergedThemes: MeditationThemeId[];
  prefs: SessionPreferences;
  prompt: string;
}): boolean {
  if (
    args.mergedThemes.includes("evening") ||
    args.mergedThemes.includes("night")
  ) {
    return true;
  }
  if (args.prefs.isEvening) return true;
  const lower = args.prompt.toLowerCase();
  return /\b(evening|wind down|after work|sunset|end of day)\b/.test(lower);
}

/**
 * Evening / end-of-day visualization (EV_KM vs EV_GR). Requires evening-ish context + viz cue
 * (or explicit LLM wantsEveningVisualization).
 */
export function resolveEveningVisualizationVariant(args: {
  prompt: string;
  llmWants?: "key_moments" | "gratitude" | null;
  mergedThemes: MeditationThemeId[];
  prefs: SessionPreferences;
}): EveningVisualizationVariant | null {
  if (args.llmWants === "gratitude") return "EV_GR";
  if (args.llmWants === "key_moments") return "EV_KM";

  if (!eveningVisualizationEveningishContext(args)) return null;

  const lower = args.prompt.toLowerCase();
  const vizCue =
    /\bvisuali[sz]ations?\b|\bvisuali[sz]e\b|\bimagin(e|ing)\b|\benvision\b|\bkey\s+moments?\b|\bguided\s+imagery\b/.test(
      lower
    );
  if (!vizCue) return null;

  const gratitudeTheme = args.mergedThemes.includes("gratitude");
  if (/gratitude|grateful|thankful/.test(lower) || gratitudeTheme) {
    return "EV_GR";
  }
  return "EV_KM";
}

export type ThemeCompositionHintsOptions = {
  /** When set, chooses MV or EV fractional row even if theme ordering would not (e.g. LLM wants*). */
  forcedFocusFractionalId?:
    | "MV_KM_FRAC"
    | "MV_GR_FRAC"
    | "EV_KM_FRAC"
    | "EV_GR_FRAC";
};

/**
 * Morning Gratitude: gratitude wins focus (MV_GR_FRAC); morning still biases intro greeting.
 * User focusType IM/NF overrides focus fractional choice.
 */
export function themeCompositionHints(
  themes: MeditationThemeId[],
  prefs: SessionPreferences,
  overrides: UserStructureOverrides,
  focusMinutes: number,
  options?: ThemeCompositionHintsOptions
): {
  fractionalContext: FractionalCompositionContext;
  cueHints: ThemeCompositionHints;
} {
  const userChoseImNf =
    overrides.focusType === "IM" || overrides.focusType === "NF";
  const sleepish = prefs.isSleep || themes.includes("sleep");

  const fractionalContext: FractionalCompositionContext = {};
  if (!sleepish) {
    if (themes.includes("morning")) {
      fractionalContext.greetingFamilyHint = "morning";
    } else if (themes.includes("evening")) {
      fractionalContext.greetingFamilyHint = "evening";
    } else if (themes.includes("noon")) {
      fractionalContext.greetingFamilyHint = "neutral";
    }
  }

  const cueHints: ThemeCompositionHints = {};

  if (focusMinutes > 0 && !sleepish && !userChoseImNf) {
    if (options?.forcedFocusFractionalId) {
      cueHints.focusFractionalId = options.forcedFocusFractionalId;
    } else if (
      themes.includes("gratitude") &&
      (themes.includes("evening") ||
        themes.includes("night") ||
        prefs.isEvening)
    ) {
      cueHints.focusFractionalId = "EV_GR_FRAC";
    } else if (themes.includes("gratitude")) {
      cueHints.focusFractionalId = "MV_GR_FRAC";
    } else if (themes.includes("morning")) {
      cueHints.focusFractionalId = "MV_KM_FRAC";
    } else if (
      themes.includes("evening") ||
      themes.includes("night") ||
      prefs.isEvening
    ) {
      cueHints.focusFractionalId = "EV_KM_FRAC";
    }
  }

  return { fractionalContext, cueHints };
}
