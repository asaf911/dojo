/**
 * Deterministic phase allocation for meditation structure.
 * Flow: Intro > Breath > Relax > Focus > Insight
 */

export interface SessionPreferences {
  noBreathwork: boolean;
  isSleep: boolean;
  isMorning: boolean;
  isEvening: boolean;
}

/** User-explicit structure requirements extracted by AI. Highest priority over defaults. */
export interface UserStructureOverrides {
  totalDuration?: number;
  mantraMinutes?: number;
  bodyScanMinutes?: number;
  breathMinutes?: number;
  focusType?: "IM" | "NF";
}

export interface PhaseAllocation {
  /** Reserved for analytics; intro audio is a session prefix, not a deducted practice minute. */
  intro: 0;
  breath: number;
  relax: number;
  focus: number;
  insight: number;
  /** When user explicitly requested mantra or nostril focus */
  focusType?: "IM" | "NF";
}

/**
 * Lookup table for 1–10 min practice: phase minutes sum to **session duration** (no separate “intro minute”).
 * INT_FRAC length is a dynamic prefix on the playback clock, not subtracted here.
 */
const ALLOCATION_1_10: Record<number, Omit<PhaseAllocation, "intro">> = {
  1: { breath: 1, relax: 0, focus: 0, insight: 0 },
  2: { breath: 2, relax: 0, focus: 0, insight: 0 },
  3: { breath: 2, relax: 1, focus: 0, insight: 0 },
  4: { breath: 2, relax: 2, focus: 0, insight: 0 },
  5: { breath: 2, relax: 2, focus: 1, insight: 0 },
  6: { breath: 2, relax: 2, focus: 2, insight: 0 },
  7: { breath: 2, relax: 2, focus: 2, insight: 1 },
  8: { breath: 2, relax: 2, focus: 2, insight: 2 },
  9: { breath: 3, relax: 2, focus: 2, insight: 2 },
  10: { breath: 3, relax: 2, focus: 2, insight: 3 },
};

/**
 * Allocates minutes to each phase based on duration and preferences.
 * noBreathwork: breath=0, redistribute proportionally to relax/focus/insight.
 */
export function allocatePhases(
  duration: number,
  prefs: SessionPreferences
): PhaseAllocation {
  const d = Math.max(1, Math.min(60, Math.floor(duration)));
  let breath: number;
  let relax: number;
  let focus: number;
  let insight: number;

  if (d <= 10) {
    const base = ALLOCATION_1_10[d];
    breath = base.breath;
    relax = base.relax;
    focus = base.focus;
    insight = base.insight;
  } else {
    const remaining = d;
    breath = Math.max(0, Math.floor(remaining * 0.2));
    relax = Math.max(0, Math.floor(remaining * 0.25));
    focus = Math.max(0, Math.floor(remaining * 0.25));
    insight = Math.max(0, remaining - breath - relax - focus);
  }

  if (prefs.noBreathwork && breath > 0) {
    const total = relax + focus + insight;
    if (total > 0) {
      const r = relax / total;
      const f = focus / total;
      const i = insight / total;
      const dr = Math.floor(breath * r);
      const df = Math.floor(breath * f);
      const di = Math.floor(breath * i);
      let remainder = breath - dr - df - di;
      relax += dr;
      focus += df;
      insight += di;
      while (remainder > 0) {
        if (relax >= focus && relax >= insight) {
          relax++;
        } else if (focus >= insight) {
          focus++;
        } else {
          insight++;
        }
        remainder--;
      }
    } else {
      relax += breath;
    }
    breath = 0;
  }

  return {
    intro: 0,
    breath: Math.min(5, breath),
    relax: Math.min(10, relax),
    focus: Math.min(10, focus),
    insight: Math.min(10, insight),
    focusType: undefined,
  };
}

/**
 * Builds allocation from user-explicit overrides. User requests take highest priority.
 * Remaining time (after intro + user-specified modules) is distributed to other phases.
 */
export function allocatePhasesFromOverrides(
  duration: number,
  overrides: UserStructureOverrides,
  prefs: SessionPreferences
): PhaseAllocation {
  const d = Math.max(1, Math.min(60, Math.floor(duration)));
  let breath = overrides.breathMinutes ?? 0;
  let relax = overrides.bodyScanMinutes ?? 0;
  let focus = overrides.mantraMinutes ?? 0;
  let insight = 0;

  let used = breath + relax + focus;
  let remaining = d - used;

  if (remaining > 0) {
    const needBreath = (overrides.breathMinutes == null) && !prefs.noBreathwork;
    const needRelax = overrides.bodyScanMinutes == null;
    const needFocus = overrides.mantraMinutes == null;

    if (needBreath && needRelax && needFocus) {
      const base = ALLOCATION_1_10[Math.min(d, 10)] ?? ALLOCATION_1_10[10];
      breath = Math.min(5, base.breath);
      relax = Math.min(10, base.relax);
      focus = Math.min(10, base.focus);
      insight = Math.min(10, base.insight);
      return {
        intro: 0,
        breath,
        relax,
        focus,
        insight,
        focusType: overrides.focusType,
      };
    }
    if (needBreath && !prefs.noBreathwork && remaining > 0) {
      breath = Math.min(5, Math.min(remaining, Math.floor(remaining * 0.5)));
      remaining -= breath;
    }
    if (needRelax && remaining > 0) {
      relax = Math.min(10, remaining);
      remaining -= relax;
    }
    if (needFocus && remaining > 0) {
      focus = Math.min(10, Math.max(overrides.focusType === "NF" ? 1 : 2, focus + remaining));
    }
  }

  if (remaining < 0) {
    // User requested more than total duration — cap to fit
    const over = -remaining;
    if (focus >= over) {
      focus -= over;
    } else {
      const reduceRelax = over - focus;
      focus = 0;
      relax = Math.max(0, relax - reduceRelax);
    }
  }

  if (prefs.noBreathwork) {
    relax += breath;
    breath = 0;
  }

  return {
    intro: 0,
    breath: Math.min(5, breath),
    relax: Math.min(10, relax),
    focus: Math.min(10, focus),
    insight: Math.min(10, insight),
    focusType: overrides.focusType,
  };
}

/**
 * Extracts session preferences from user prompt (regex-based).
 */
export function extractSessionPreferences(prompt: string): SessionPreferences {
  const lower = prompt.toLowerCase();
  return {
    noBreathwork:
      /no\s*breathwork|without\s*breathwork|skip\s*breath(ing)?|no\s*breath(ing)?|remove\s*breath(work|ing)?/.test(
        lower
      ) ||
      lower.includes("no breath") ||
      lower.includes("without breath") ||
      lower.includes("remove breath"),
    isSleep:
      /sleep|nap|bedtime|fall asleep|drift off|slumber|insomnia|good\s+night/.test(
        lower
      ),
    isMorning: /morning|wake up|start day|energize|sunrise/.test(lower),
    isEvening: /evening|wind down|after work|sunset|end of day/.test(lower),
  };
}

/**
 * Extracts duration in minutes from user prompt.
 * Matches: "20m", "20 min", "20 minute", "20-minute", "20min", "20 minutes"
 * Fallback: null if not found.
 */
export function extractDurationFromPrompt(prompt: string): number | null {
  const patterns = [
    /\b(\d+)\s*[-]?\s*(?:min(?:ute)?s?|m)\b/i,
    /\b(?:a\s+)?(\d+)\s*[-]?\s*minute\s+meditation\b/i,
    /\b(\d+)\s*[-]?\s*minute\b/i,
    /\b(\d+)\s*m\b/i,
    /\b(\d+)\s*min\b/i,
  ];

  for (const pattern of patterns) {
    const match = prompt.match(pattern);
    if (match) {
      const n = parseInt(match[1], 10);
      if (n >= 1 && n <= 60) return n;
    }
  }

  if (/^\d+$/.test(prompt.trim())) {
    const n = parseInt(prompt.trim(), 10);
    if (n >= 1 && n <= 60) return n;
  }

  return null;
}

/**
 * Extracts duration from conversation history (last assistant message).
 * Used when prompt is a modification (e.g. "remove breathwork") and doesn't contain duration.
 */
export function extractDurationFromConversationHistory(
  history: Array<{ role: string; content: string }>
): number | null {
  for (let i = history.length - 1; i >= 0; i--) {
    if (history[i].role === "assistant") {
      const n = extractDurationFromPrompt(history[i].content);
      if (n != null) return n;
    }
  }
  return null;
}
