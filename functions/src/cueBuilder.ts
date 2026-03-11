/**
 * Maps phase allocation to cue IDs and triggers.
 * Flow: Intro > Breath > Relax > Focus > Insight > GB (unless sleep)
 */

import type { PhaseAllocation, SessionPreferences } from "./phaseAllocation";

export interface CueWithTrigger {
  id: string;
  trigger: string;
}

const PB_CAP = 5;
const BS_CAP = 10;
const IM_MIN = 2;
const IM_CAP = 10;

/**
 * Builds cues from allocation. Clamps durations to available catalog variants.
 * isSleep: Use OH for focus, skip GB. Plan: default IM2 or NF2 for focus.
 */
export function buildCuesFromAllocation(
  allocation: PhaseAllocation,
  prefs: SessionPreferences
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
    cues.push({ id: `BS${relax}`, trigger: String(currentMinute) });
    currentMinute += relax;
  }

  if (prefs.isSleep && (focus > 0 || relax > 0 || breath > 0)) {
    cues.push({ id: "OH", trigger: String(currentMinute) });
    currentMinute += 1;
  } else if (focus > 0) {
    const n = Math.max(IM_MIN, Math.min(IM_CAP, focus));
    cues.push({ id: `IM${n}`, trigger: String(currentMinute) });
    currentMinute += n;
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
