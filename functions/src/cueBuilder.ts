/**
 * Maps phase allocation to cue IDs and triggers.
 * Flow: Intro > Breath > Relax > Focus (legacy VC/RT/OH insight cues retired — GB optional in Timer only).
 */

import type { PhaseAllocation, SessionPreferences } from "./phaseAllocation";
import type { ThemeCompositionHints } from "./meditationThemes";
import { useFractionalModulesInCatalogsAndAI } from "./deploymentMode";

export interface CueWithTrigger {
  id: string;
  trigger: string;
  /** Set for BS_FRAC_* so expandFractionalCues gets the relax-phase window in minutes. */
  durationMinutes?: number;
}

export interface BuildCuesFromAllocationOptions {
  /**
   * Semantic from AI extract: `"down"` = top→bottom (→ BS_FRAC_DOWN), `"up"` = bottom→top (→ BS_FRAC_UP).
   * Omit for pseudo-random cue choice.
   */
  bodyScanDirection?: "up" | "down";
  /**
   * Practice duration in minutes. When set to 1–4, fractional AI sessions omit `INT_FRAC`; 5+ include it.
   * Omit to default to 10 (preserves prior behavior for callers that do not pass duration).
   */
  practiceDurationMinutes?: number;
  /**
   * Theme-driven focus rows. User `allocation.focusType` IM/NF always wins over focus fractional hint.
   */
  themeCueHints?: ThemeCompositionHints;
}

const PB_CAP = 5;
const BS_CAP = 10;
const IM_CAP = 10;

/**
 * Retired monolithic insight trigger cues (VC/RT/OH): fold planned `insight` minutes into earlier phases
 * so totals still match the session duration.
 */
function allocationWithInsightMergedIntoEarlierPhases(
  allocation: PhaseAllocation
): PhaseAllocation {
  let breath = allocation.breath;
  let relax = allocation.relax;
  let focus = allocation.focus;
  let insight = allocation.insight;
  if (insight <= 0) return allocation;

  let rest = insight;
  insight = 0;

  const addFocus = Math.min(IM_CAP - focus, rest);
  focus += addFocus;
  rest -= addFocus;

  if (rest > 0) {
    const addRelax = Math.min(BS_CAP - relax, rest);
    relax += addRelax;
    rest -= addRelax;
  }
  if (rest > 0) {
    const addBreath = Math.min(PB_CAP - breath, rest);
    breath += addBreath;
    rest -= addBreath;
  }

  while (rest > 0) {
    if (focus < IM_CAP) {
      focus++;
      rest--;
    } else if (relax < BS_CAP) {
      relax++;
      rest--;
    } else if (breath < PB_CAP) {
      breath++;
      rest--;
    } else {
      break;
    }
  }

  return {
    ...allocation,
    breath,
    relax,
    focus,
    insight: 0,
    focusType: allocation.focusType,
  };
}

/**
 * Production: monolithic INT_GEN_1/INT_MORN_1, PBn, BSn, IMn/NFn.
 * Dev project: fractional INT_FRAC, PB_FRAC, BS_FRAC_*, IM_FRAC/NF_FRAC or NFn.
 */
export function buildCuesFromAllocation(
  allocation: PhaseAllocation,
  prefs: SessionPreferences,
  options?: BuildCuesFromAllocationOptions
): CueWithTrigger[] {
  if (useFractionalModulesInCatalogsAndAI()) {
    return buildCuesFromAllocationFractional(allocation, prefs, options);
  }
  return buildCuesFromAllocationLegacy(allocation, prefs, options);
}

function buildCuesFromAllocationLegacy(
  allocation: PhaseAllocation,
  prefs: SessionPreferences,
  options?: BuildCuesFromAllocationOptions
): CueWithTrigger[] {
  const merged = allocationWithInsightMergedIntoEarlierPhases(allocation);
  const cues: CueWithTrigger[] = [];
  /// Practice-minute index: 0 = meditation clock 00:00 (INT_FRAC prelude uses negative countdown / prefix).
  let currentMinute = 0;

  const introId = prefs.isMorning ? "INT_MORN_1" : "INT_GEN_1";
  cues.push({ id: introId, trigger: "start" });

  const breath = Math.min(PB_CAP, Math.max(0, merged.breath));
  const relax = Math.min(BS_CAP, Math.max(0, merged.relax));
  const focus = Math.min(IM_CAP, Math.max(0, merged.focus));

  if (breath > 0) {
    const pbVariant = Math.min(5, Math.max(1, breath));
    cues.push({
      id: `PB${pbVariant}`,
      trigger: String(currentMinute),
    });
    currentMinute += breath;
  }

  if (relax > 0) {
    const bsVariant = Math.min(10, Math.max(1, relax));
    cues.push({
      id: `BS${bsVariant}`,
      trigger: String(currentMinute),
    });
    currentMinute += relax;
  }

  if (focus > 0) {
    if (merged.focusType === "NF") {
      const nfVariant = Math.min(10, Math.max(1, focus));
      cues.push({ id: `NF${nfVariant}`, trigger: String(currentMinute) });
    } else {
      const imVariant = Math.min(10, Math.max(2, focus));
      cues.push({ id: `IM${imVariant}`, trigger: String(currentMinute) });
    }
    currentMinute += Math.min(10, focus);
  }

  return cues;
}

/**
 * Dev/fractional path: `INT_FRAC@start` is included only when `practiceDurationMinutes` is 5 or higher
 * (default 10 when omitted). For AI sessions 1–4 minutes, omit the option or pass 1–4 so the first
 * content cue sits at practice minute 0 without a fractional intro row.
 */
function buildCuesFromAllocationFractional(
  allocation: PhaseAllocation,
  _prefs: SessionPreferences,
  options?: BuildCuesFromAllocationOptions
): CueWithTrigger[] {
  const merged = allocationWithInsightMergedIntoEarlierPhases(allocation);
  const cues: CueWithTrigger[] = [];
  /// Practice-minute index: 0 = first module at meditation 00:00 (or first content when INT_FRAC omitted for short AI sessions).
  let currentMinute = 0;

  const practiceMin = options?.practiceDurationMinutes ?? 10;
  const includeIntroFrac = practiceMin >= 5;
  if (includeIntroFrac) {
    cues.push({ id: "INT_FRAC", trigger: "start" });
  }

  const breath = Math.min(PB_CAP, Math.max(0, merged.breath));
  const relax = Math.min(BS_CAP, Math.max(0, merged.relax));
  const focus = Math.min(IM_CAP, Math.max(0, merged.focus));

  if (breath > 0) {
    cues.push({
      id: "PB_FRAC",
      trigger: String(currentMinute),
      durationMinutes: breath,
    });
    currentMinute += breath;
  }

  if (relax > 0) {
    const dir =
      options?.bodyScanDirection === "up" ||
      options?.bodyScanDirection === "down"
        ? options.bodyScanDirection
        : Math.random() < 0.5
          ? "up"
          : "down";
    const bodyScanId = dir === "down" ? "BS_FRAC_DOWN" : "BS_FRAC_UP";
    cues.push({
      id: bodyScanId,
      trigger: String(currentMinute),
      durationMinutes: relax,
    });
    currentMinute += relax;
  }

  if (focus > 0) {
    const focusFrac =
      options?.themeCueHints?.focusFractionalId &&
      merged.focusType !== "NF" &&
      merged.focusType !== "IM"
        ? options.themeCueHints.focusFractionalId
        : merged.focusType === "NF"
          ? "NF_FRAC"
          : "IM_FRAC";
    cues.push({ id: focusFrac, trigger: String(currentMinute) });
    currentMinute += Math.min(10, focus);
  }

  return cues;
}
