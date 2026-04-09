/**
 * Rewrites fractional surface cue ids (NF_FRAC, PB_FRAC, IM_FRAC, BS_FRAC*) to monolithic
 * catalog ids so stale clients work against production catalogs.
 */

export interface FractionalSurfaceCueLike {
  id: string;
  trigger: string | number;
  durationMinutes?: number;
}

export function triggerToSeconds(trigger: string | number): number | null {
  if (trigger === "start") return 0;
  if (trigger === "end") return null;
  if (typeof trigger === "number") return trigger * 60;
  if (typeof trigger === "string") {
    if (trigger.startsWith("s")) {
      const n = parseInt(trigger.slice(1), 10);
      return isNaN(n) ? null : n;
    }
    const n = parseInt(trigger, 10);
    return isNaN(n) ? null : n * 60;
  }
  return null;
}

function windowMinutesForCue(
  cues: FractionalSurfaceCueLike[],
  index: number,
  sessionDurationMinutes: number,
  minK: number,
  maxK: number
): number {
  const durationSec = sessionDurationMinutes * 60;
  const cue = cues[index];
  const startSec = triggerToSeconds(cue.trigger) ?? 0;

  let endSec: number;
  const dm =
    typeof cue.durationMinutes === "number" && cue.durationMinutes > 0
      ? cue.durationMinutes
      : undefined;
  if (dm !== undefined) {
    endSec = Math.min(startSec + dm * 60, durationSec);
  } else {
    endSec = durationSec;
    for (let j = index + 1; j < cues.length; j++) {
      const nextSec = triggerToSeconds(cues[j].trigger);
      if (nextSec !== null && nextSec > startSec) {
        endSec = nextSec;
        break;
      }
    }
  }

  const windowSec = Math.max(0, endSec - startSec);
  const rounded = Math.round(windowSec / 60);
  const k = rounded || minK;
  return Math.min(maxK, Math.max(minK, k));
}

const FRAC_IDS_TO_REWRITE = new Set([
  "NF_FRAC",
  "PB_FRAC",
  "IM_FRAC",
  "BS_FRAC",
  "BS_FRAC_UP",
  "BS_FRAC_DOWN",
]);

/**
 * Maps fractional placeholder ids → monolithic ids for production catalog resolution.
 */
export function normalizeFractionalSurfaceCueIdsForProd<T extends FractionalSurfaceCueLike>(
  cues: T[],
  sessionDurationMinutes: number
): T[] {
  if (!cues.some((c) => FRAC_IDS_TO_REWRITE.has(c.id))) {
    return cues;
  }
  return cues.map((c, i) => {
    if (c.id === "NF_FRAC") {
      const k = windowMinutesForCue(cues, i, sessionDurationMinutes, 1, 10);
      return { ...c, id: `NF${k}` };
    }
    if (c.id === "PB_FRAC") {
      const k = windowMinutesForCue(cues, i, sessionDurationMinutes, 1, 5);
      return { ...c, id: `PB${k}` };
    }
    if (c.id === "IM_FRAC") {
      const k = windowMinutesForCue(cues, i, sessionDurationMinutes, 2, 10);
      return { ...c, id: `IM${k}` };
    }
    if (
      c.id === "BS_FRAC" ||
      c.id === "BS_FRAC_UP" ||
      c.id === "BS_FRAC_DOWN"
    ) {
      const k = windowMinutesForCue(cues, i, sessionDurationMinutes, 1, 10);
      return { ...c, id: `BS${k}` };
    }
    return c;
  });
}

/** @deprecated use normalizeFractionalSurfaceCueIdsForProd */
export function normalizeLegacyNostrilFracCueIds<T extends FractionalSurfaceCueLike>(
  cues: T[],
  sessionDurationMinutes: number
): T[] {
  return normalizeFractionalSurfaceCueIdsForProd(cues, sessionDurationMinutes);
}
