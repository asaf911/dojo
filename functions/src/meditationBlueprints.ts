/**
 * Single source of truth for product meditation templates (timely + future scenarios).
 * Drives cue focus hints, optional dual focus (night), and background / binaural preferences.
 */

import type { SessionPreferences } from "./phaseAllocation";
import type {
  FractionalCompositionContext,
  MeditationThemeId,
  ThemeCompositionHints,
} from "./meditationThemes";

/** Known blueprint ids (extend for new scenarios). */
export const BLUEPRINT_IDS = [
  "timely.morning",
  "timely.noon",
  "timely.evening",
  "timely.night",
  "timely.sleep",
  "scenario.pre_important_event",
] as const;

export type BlueprintId = (typeof BLUEPRINT_IDS)[number];

export type BackgroundSoundCategory = "calming" | "focus" | "sleep";

/** Aligns with iOS `ai_composition_guidelines.json` `sound_categories`. */
export const BACKGROUND_SOUND_CATEGORIES: Record<
  BackgroundSoundCategory,
  readonly string[]
> = {
  calming: ["SP", "OC", "BD"],
  focus: ["LI", "DH"],
  sleep: ["OC", "BD"],
};

export interface AudioHints {
  backgroundSound?: {
    preferCategory?: BackgroundSoundCategory;
    preferredIds?: readonly string[];
    avoidIds?: readonly string[];
  };
  binauralBeat?: {
    preferredIds?: readonly string[];
  };
}

export type TerminalMode =
  | "MV_KM"
  | "MV_GR"
  | "EV_KM"
  | "EV_GR"
  | "IM_FOCUS"
  /** IM first, then evening visualization (split focus minutes in cue builder). */
  | "NIGHT_IM_THEN_EV"
  /** Sleep / wind-down: no MV/EV row; audio only bias from blueprint. */
  | "SLEEP_AMBIENT";

export interface MeditationBlueprint {
  readonly id: BlueprintId;
  /** Product arc labels (documentation / logs). */
  readonly phaseIntent: readonly string[];
  readonly terminalMode: TerminalMode;
  readonly audioHints: AudioHints;
}

const BLUEPRINTS: Record<BlueprintId, MeditationBlueprint> = {
  "timely.morning": {
    id: "timely.morning",
    phaseIntent: ["intro", "breath", "relax", "morning_visualization"],
    terminalMode: "MV_KM",
    audioHints: {
      backgroundSound: { preferCategory: "focus", preferredIds: ["LI", "DH"] },
      binauralBeat: { preferredIds: ["BB10", "BB12"] },
    },
  },
  "timely.noon": {
    id: "timely.noon",
    phaseIntent: ["intro", "breath", "relax", "focus"],
    terminalMode: "IM_FOCUS",
    audioHints: {
      backgroundSound: { preferCategory: "focus", preferredIds: ["LI", "DH"] },
      binauralBeat: { preferredIds: ["BB10", "BB14"] },
    },
  },
  "timely.evening": {
    id: "timely.evening",
    phaseIntent: ["intro", "breath", "relax", "evening_visualization"],
    terminalMode: "EV_KM",
    audioHints: {
      backgroundSound: { preferCategory: "calming", preferredIds: ["OC", "SP", "BD"] },
      binauralBeat: { preferredIds: ["BB8", "BB10"] },
    },
  },
  "timely.night": {
    id: "timely.night",
    phaseIntent: ["intro", "breath", "relax", "focus", "evening_visualization"],
    terminalMode: "NIGHT_IM_THEN_EV",
    audioHints: {
      backgroundSound: { preferCategory: "calming", preferredIds: ["OC", "BD", "SP"] },
      binauralBeat: { preferredIds: ["BB8", "BB6"] },
    },
  },
  "timely.sleep": {
    id: "timely.sleep",
    phaseIntent: ["intro", "breath", "relax", "sleep"],
    terminalMode: "SLEEP_AMBIENT",
    audioHints: {
      backgroundSound: { preferCategory: "sleep", preferredIds: ["OC", "BD"] },
      binauralBeat: { preferredIds: ["BB4", "BB6"] },
    },
  },
  "scenario.pre_important_event": {
    id: "scenario.pre_important_event",
    phaseIntent: ["intro", "breath", "relax", "focus"],
    terminalMode: "IM_FOCUS",
    audioHints: {
      backgroundSound: { preferCategory: "focus", preferredIds: ["LI", "SP"] },
      binauralBeat: { preferredIds: ["BB12", "BB14"] },
    },
  },
};

function isBlueprintId(s: string): s is BlueprintId {
  return (BLUEPRINT_IDS as readonly string[]).includes(s);
}

export function parseClientBlueprintId(
  raw: string | null | undefined
): BlueprintId | null {
  if (!raw) return null;
  const id = raw.trim();
  return isBlueprintId(id) ? id : null;
}

/**
 * Resolve active blueprint: explicit client id wins, else first matching timely template from themes + prefs.
 */
export function resolveBlueprintFromContext(args: {
  clientBlueprintId?: string | null;
  themes: readonly MeditationThemeId[];
  prefs: SessionPreferences;
}): MeditationBlueprint | null {
  const fromClient = parseClientBlueprintId(args.clientBlueprintId ?? undefined);
  if (fromClient) return BLUEPRINTS[fromClient];

  const t = new Set(args.themes.map((x) => String(x).trim().toLowerCase()));
  if (args.prefs.isSleep || t.has("sleep")) return BLUEPRINTS["timely.sleep"];
  if (t.has("morning")) return BLUEPRINTS["timely.morning"];
  if (t.has("noon")) return BLUEPRINTS["timely.noon"];
  if (t.has("evening")) return BLUEPRINTS["timely.evening"];
  if (t.has("night")) return BLUEPRINTS["timely.night"];
  return null;
}

export function getBlueprintById(id: BlueprintId): MeditationBlueprint {
  return BLUEPRINTS[id];
}

/** Map blueprint terminal to visualization key used by `generateAIMeditation` (null = no viz row / use defaults). */
export type VizChosen = "MV_KM" | "MV_GR" | "EV_KM" | "EV_GR";

export function vizChosenForBlueprintTerminal(
  blueprint: MeditationBlueprint,
  themes: readonly MeditationThemeId[]
): VizChosen | null {
  const t = new Set(themes.map((x) => String(x).trim().toLowerCase()));
  const gratitude = t.has("gratitude");

  switch (blueprint.terminalMode) {
    case "MV_KM":
      return gratitude ? "MV_GR" : "MV_KM";
    case "EV_KM":
      return gratitude ? "EV_GR" : "EV_KM";
    case "NIGHT_IM_THEN_EV":
      // Rebalance steals relax for the **evening viz** window; first block is IM in cue builder.
      return gratitude ? "EV_GR" : "EV_KM";
    case "IM_FOCUS":
    case "SLEEP_AMBIENT":
      return null;
    case "MV_GR":
      return "MV_GR";
    case "EV_GR":
      return "EV_GR";
    default:
      return null;
  }
}

export type BlueprintCueHintMerge = {
  fractionalContext: FractionalCompositionContext;
  cueHints: ThemeCompositionHints;
};

/**
 * Cue / intro hints from blueprint. Caller merges over base `themeCompositionHints` when non-empty.
 * Respects user IM/NF choice: pass `userChoseImNf` true to skip blueprint focus rows (user path).
 */
export function getBlueprintCueHintMerge(args: {
  blueprint: MeditationBlueprint;
  themes: readonly MeditationThemeId[];
  prefs: SessionPreferences;
  focusMinutes: number;
  userChoseImNf: boolean;
}): BlueprintCueHintMerge | null {
  const { blueprint, themes, prefs, focusMinutes, userChoseImNf } = args;
  const sleepish = prefs.isSleep || themes.map((x) => x.toLowerCase()).includes("sleep");
  const tset = new Set(themes.map((x) => String(x).trim().toLowerCase()));

  const out: BlueprintCueHintMerge = {
    fractionalContext: {},
    cueHints: {},
  };

  if (blueprint.id === "timely.sleep" || blueprint.terminalMode === "SLEEP_AMBIENT") {
    return out;
  }

  if (!sleepish) {
    if (tset.has("morning") || blueprint.id === "timely.morning") {
      out.fractionalContext.greetingFamilyHint = "morning";
    } else if (tset.has("evening") || blueprint.id === "timely.evening") {
      out.fractionalContext.greetingFamilyHint = "evening";
    } else if (tset.has("noon") || blueprint.id === "timely.noon") {
      out.fractionalContext.greetingFamilyHint = "neutral";
    } else if (blueprint.id === "timely.night") {
      out.fractionalContext.greetingFamilyHint = "neutral";
    } else if (blueprint.id === "scenario.pre_important_event") {
      out.fractionalContext.greetingFamilyHint = "neutral";
    }
  }

  if (focusMinutes <= 0 || sleepish || userChoseImNf) {
    return out;
  }

  if (blueprint.terminalMode === "NIGHT_IM_THEN_EV" && focusMinutes >= 2) {
    out.cueHints.secondFocusFractionalId =
      tset.has("gratitude") && !tset.has("morning")
        ? "EV_GR_FRAC"
        : "EV_KM_FRAC";
    return out;
  }

  const gratitude = tset.has("gratitude");
  switch (blueprint.terminalMode) {
    case "MV_KM":
      out.cueHints.focusFractionalId = gratitude ? "MV_GR_FRAC" : "MV_KM_FRAC";
      break;
    case "MV_GR":
      out.cueHints.focusFractionalId = "MV_GR_FRAC";
      break;
    case "EV_KM":
      out.cueHints.focusFractionalId = gratitude ? "EV_GR_FRAC" : "EV_KM_FRAC";
      break;
    case "EV_GR":
      out.cueHints.focusFractionalId = "EV_GR_FRAC";
      break;
    case "IM_FOCUS":
      // Default fractional row is IM_FRAC when no hint — leave unset
      break;
    default:
      break;
  }

  return out;
}

function baseWeightForSoundId(
  id: string | undefined,
  hints: AudioHints["backgroundSound"] | undefined,
  catalogIds: Set<string>
): number {
  if (!id || !catalogIds.has(id)) return 0;
  if (hints?.avoidIds?.includes(id)) return 0.05;
  const preferred = hints?.preferredIds ?? [];
  const idx = preferred.indexOf(id);
  if (idx >= 0) return 2.5 - idx * 0.15;
  const cat = hints?.preferCategory;
  if (cat) {
    const pool = BACKGROUND_SOUND_CATEGORIES[cat];
    if (pool.includes(id)) return 1.6;
  }
  return 1.0;
}

/**
 * Pick background sound using blueprint weights, then recent-usage down-weighting.
 */
export function pickBackgroundSoundForBlueprint<T extends { id?: string }>(
  items: T[],
  excludeId: string | undefined,
  hints: AudioHints["backgroundSound"] | undefined,
  recentlyUsedIds?: string[]
): T | undefined {
  const catalogIds = new Set(
    items.map((i) => i.id).filter((x): x is string => Boolean(x))
  );
  const filtered = excludeId
    ? items.filter((item) => item.id && item.id !== excludeId)
    : items.filter((item) => item.id);
  if (filtered.length === 0) return undefined;

  const recentSet = new Set(recentlyUsedIds ?? []);
  const weights = filtered.map((item) => {
    const id = item.id!;
    let w = baseWeightForSoundId(id, hints, catalogIds);
    if (w <= 0) w = 0.01;
    if (recentSet.has(id)) w *= 0.3;
    return w;
  });

  const total = weights.reduce((a, b) => a + b, 0);
  if (total <= 0) return filtered[Math.floor(Math.random() * filtered.length)];
  let r = Math.random() * total;
  for (let i = 0; i < filtered.length; i++) {
    r -= weights[i];
    if (r <= 0) return filtered[i];
  }
  return filtered[filtered.length - 1];
}

export function pickBinauralBeatForBlueprint<T extends { id?: string }>(
  items: T[],
  hints: AudioHints["binauralBeat"] | undefined
): T | undefined {
  const preferred = hints?.preferredIds;
  if (preferred?.length) {
    for (const pid of preferred) {
      const hit = items.find((b) => b.id === pid);
      if (hit) return hit;
    }
  }
  if (items.length === 0) return undefined;
  return items[Math.floor(Math.random() * items.length)];
}
