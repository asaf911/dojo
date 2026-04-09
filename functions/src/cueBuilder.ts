/**
 * Maps phase allocation to cue IDs and triggers.
 * Flow: Intro > Breath > Relax > Focus > Insight > GB (unless sleep)
 */

import type { PhaseAllocation, SessionPreferences } from "./phaseAllocation";
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
}

const PB_CAP = 5;
const BS_CAP = 10;
const IM_CAP = 10;

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
  const cues: CueWithTrigger[] = [];
  let currentMinute = 1;

  const introId = prefs.isMorning ? "INT_MORN_1" : "INT_GEN_1";
  cues.push({ id: introId, trigger: "start" });

  const breath = Math.min(PB_CAP, Math.max(0, allocation.breath));
  const relax = Math.min(BS_CAP, Math.max(0, allocation.relax));
  const focus = Math.min(IM_CAP, Math.max(0, allocation.focus));
  const insight = Math.min(10, Math.max(0, allocation.insight));

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

  if (prefs.isSleep && (focus > 0 || relax > 0 || breath > 0)) {
    cues.push({ id: "OH", trigger: String(currentMinute) });
    currentMinute += 1;
  } else if (focus > 0) {
    if (allocation.focusType === "NF") {
      const nfVariant = Math.min(10, Math.max(1, focus));
      cues.push({ id: `NF${nfVariant}`, trigger: String(currentMinute) });
    } else {
      const imVariant = Math.min(10, Math.max(2, focus));
      cues.push({ id: `IM${imVariant}`, trigger: String(currentMinute) });
    }
    currentMinute += Math.min(10, focus);
  }

  if (insight > 0) {
    const insightId = prefs.isEvening ? "RT" : "VC";
    cues.push({ id: insightId, trigger: String(currentMinute) });
  }

  if (!prefs.isSleep) {
    cues.push({ id: "GB", trigger: "end" });
  }

  return cues;
}

function buildCuesFromAllocationFractional(
  allocation: PhaseAllocation,
  prefs: SessionPreferences,
  options?: BuildCuesFromAllocationOptions
): CueWithTrigger[] {
  const cues: CueWithTrigger[] = [];
  let currentMinute = 1;

  cues.push({ id: "INT_FRAC", trigger: "start" });

  const breath = Math.min(PB_CAP, Math.max(0, allocation.breath));
  const relax = Math.min(BS_CAP, Math.max(0, allocation.relax));
  const focus = Math.min(IM_CAP, Math.max(0, allocation.focus));
  const insight = Math.min(10, Math.max(0, allocation.insight));

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

  if (prefs.isSleep && (focus > 0 || relax > 0 || breath > 0)) {
    cues.push({ id: "OH", trigger: String(currentMinute) });
    currentMinute += 1;
  } else if (focus > 0) {
    if (allocation.focusType === "NF") {
      cues.push({ id: "NF_FRAC", trigger: String(currentMinute) });
    } else {
      cues.push({ id: "IM_FRAC", trigger: String(currentMinute) });
    }
    currentMinute += Math.min(10, focus);
  }

  if (insight > 0) {
    const insightId = prefs.isEvening ? "RT" : "VC";
    cues.push({ id: insightId, trigger: String(currentMinute) });
  }

  if (!prefs.isSleep) {
    cues.push({ id: "GB", trigger: "end" });
  }

  return cues;
}
