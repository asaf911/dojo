/**
 * Maps phase allocation to cue IDs and triggers.
 * Flow: Intro > Breath > Relax > Focus > Insight > GB (unless sleep)
 */

import type { PhaseAllocation, SessionPreferences } from "./phaseAllocation";

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
 * Builds cues from allocation. Clamps durations to available catalog variants.
 * isSleep: Use OH for focus, skip GB. Focus emits IM_FRAC or NF_FRAC.
 */
export function buildCuesFromAllocation(
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
    cues.push({ id: `PB${breath}`, trigger: String(currentMinute) });
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
    // dir "down" = head→feet (top to bottom) → BS_FRAC_DOWN; "up" = feet→head → BS_FRAC_UP
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
