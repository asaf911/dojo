/**
 * NF_FRAC / IM_FRAC unified timeline: instruction spacing + monotonic reminder silences
 * (n+1 gaps for n reminders). Surplus silence above per-slot floors is split with linear weights
 * 1…(n+1) so the gap before outro grows modestly vs earlier gaps (no single “long tail” swallow).
 *
 * @see docs/fractional-module-composition.md
 */

export const ESTIMATED_CLIP_SEC_FALLBACK = 5;

/** Minimum gap before first reminder (seconds). */
const REMINDER_GAP_FLOOR = 22;
/** NF_FRAC: wider floor so nostril nudges breathe more slowly. */
const NF_REMINDER_GAP_FLOOR = 36;
/** IM_FRAC: higher floor so mantra practice has wider reminder spacing. */
const IM_REMINDER_GAP_FLOOR = 40;
/** Session end padding after last clip (seconds). */
const SESSION_END_PAD_SEC = 1;
/** Minimum gap after last reminder before outro starts. */
const MIN_GAP_BEFORE_OUTRO = 16;

const REM_SILENCE_SUM_EPS = 1e-3;

/** Clip fields required for scheduling (matches FractionalClip subset). */
export interface ScheduleClip {
  clipId: string;
  role: string;
  text: string;
  voices: Record<string, string>;
  durationSec?: number;
  order?: number;
  priority?: "p0" | "p1" | "p2";
}

export interface NfImPlanItem {
  atSec: number;
  clipId: string;
  role: string;
  text: string;
  url: string;
}

/**
 * Optional silence between consecutive instruction clips (moduleId → "from|to" → sec).
 */
export const FRACTIONAL_INSTRUCTION_PAIR_GAPS: Record<string, Record<string, number>> = {
  IM_FRAC: { "IM_C002|IM_C003": 5 },
};

export function clipDurationSec(clip: ScheduleClip): number {
  const d = clip.durationSec;
  if (d != null && Number.isFinite(d) && d > 0) {
    return d;
  }
  return ESTIMATED_CLIP_SEC_FALLBACK;
}

function instructionPairGapSec(
  moduleId: string,
  fromClipId: string,
  toClipId: string
): number | undefined {
  const key = `${fromClipId}|${toClipId}`;
  const v = FRACTIONAL_INSTRUCTION_PAIR_GAPS[moduleId]?.[key];
  return v != null && Number.isFinite(v) ? v : undefined;
}

/** Exponential instruction-gap curve (seconds), shared by fractional composers. */
export function instrGapAt(durationSec: number, step: number): number {
  const dFactor = Math.min(1, Math.max(0, (durationSec - 600) / 600));
  const instrBase = 6 + 2 * dFactor;
  const INSTR_CAP = 30;
  return Math.min(instrBase + Math.pow(2, step) - 1, INSTR_CAP);
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

/**
 * Per-slot minimum silence (seconds) for reminder placement. Callers typically combine with an
 * instruction baseline via `Math.max(baseline, floors.*)` so reminder gaps never sit below the
 * tightest instruction gap in the chain.
 */
export interface ReminderSilenceFloors {
  beforeFirst: number;
  between: number;
  afterLast: number;
}

/**
 * For `n` reminders, returns `n + 1` silences: after instructions before R₀, between Rᵢ and Rᵢ₊₁,
 * then after the last reminder before the segment end (outro or session end).
 *
 * Floors are raised to a non-decreasing sequence. Remaining budget is split with weights
 * `1, 2, …, n+1` (arithmetic progression on the **extra** above floors), so later gaps get more
 * silence but no single slot absorbs the whole surplus.
 */
export function allocateReminderSilencesWithLongTail(
  totalSilenceSec: number,
  nReminders: number,
  floors: ReminderSilenceFloors
): number[] | null {
  if (nReminders <= 0) {
    return [];
  }
  const n = nReminders;
  const s: number[] = [floors.beforeFirst];
  for (let i = 1; i < n; i++) {
    s.push(floors.between);
  }
  s.push(floors.afterLast);
  for (let i = 1; i < s.length; i++) {
    if (s[i]! < s[i - 1]!) {
      s[i] = s[i - 1]!;
    }
  }
  const minSum = s.reduce((a, b) => a + b, 0);
  if (totalSilenceSec + REM_SILENCE_SUM_EPS < minSum) {
    return null;
  }
  const extra = totalSilenceSec - minSum;
  const weightSum = ((n + 1) * (n + 2)) / 2;
  for (let i = 0; i <= n; i++) {
    const w = i + 1;
    s[i] = (s[i] ?? 0) + (extra * w) / weightSum;
  }
  return s;
}

export interface ScheduleNfImResult {
  items: NfImPlanItem[];
  /** End time of last scheduled clip audio (max start + duration). */
  timelineEndSec: number;
  fits: boolean;
}

/**
 * Build plan items for NF/IM using one schedule: exponential instruction gaps (with pair overrides),
 * then reminder gaps (floors + linear-weight surplus) before outro/session end.
 */
export function scheduleNfImPlan(
  selected: ScheduleClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string
): ScheduleNfImResult {
  if (selected.length === 0) {
    return { items: [], timelineEndSec: 0, fits: true };
  }

  const instrClips = selected.filter(
    (c) => c.role === "intro" || c.role === "instruction"
  );
  const reminderClips = selected.filter((c) => c.role === "reminder");
  const outroClips = selected.filter((c) => c.role === "outro");

  const items: NfImPlanItem[] = [];
  /** End time of last clip on a float timeline (avoids rounding drift between gaps). */
  let cursorEnd = 0;
  let timelineEndSec = 0;

  const pushItem = (startFloat: number, clip: ScheduleClip) => {
    const url = clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
    const startDisplayed = Math.round(startFloat);
    items.push({
      atSec: startDisplayed,
      clipId: clip.clipId,
      role: clip.role,
      text: clip.text,
      url,
    });
    const endFloat = startFloat + clipDurationSec(clip);
    timelineEndSec = Math.max(
      timelineEndSec,
      startDisplayed + clipDurationSec(clip)
    );
    return endFloat;
  };

  for (let i = 0; i < instrClips.length; i++) {
    const clip = instrClips[i];
    if (i === 0) {
      cursorEnd = pushItem(0, clip);
    } else {
      const prev = instrClips[i - 1];
      const pair = instructionPairGapSec(moduleId, prev.clipId, clip.clipId);
      const gap =
        pair !== undefined ? pair : instrGapAt(durationSec, i - 1);
      cursorEnd = pushItem(cursorEnd + gap, clip);
    }
  }

  let instrBaseline = instrGapAt(durationSec, 0);
  if (instrClips.length >= 2) {
    const gaps: number[] = [];
    for (let i = 1; i < instrClips.length; i++) {
      const prev = instrClips[i - 1]!;
      const cur = instrClips[i]!;
      const pair = instructionPairGapSec(moduleId, prev.clipId, cur.clipId);
      gaps.push(pair !== undefined ? pair : instrGapAt(durationSec, i - 1));
    }
    instrBaseline = Math.min(...gaps);
  }

  const reminderGapFloor =
    moduleId === "IM_FRAC"
      ? IM_REMINDER_GAP_FLOOR
      : moduleId === "NF_FRAC"
        ? NF_REMINDER_GAP_FLOOR
        : REMINDER_GAP_FLOOR;

  const outroClip = outroClips[0];
  const outroDur = outroClip ? clipDurationSec(outroClip) : 0;

  if (reminderClips.length > 0) {
    const n = reminderClips.length;
    const sumRemD = reminderClips.reduce((s, c) => s + clipDurationSec(c), 0);

    const segmentEnd = outroClip
      ? durationSec - SESSION_END_PAD_SEC - outroDur
      : durationSec - SESSION_END_PAD_SEC;

    const totalSilence = segmentEnd - cursorEnd - sumRemD;
    if (totalSilence < -REM_SILENCE_SUM_EPS) {
      return { items, timelineEndSec, fits: false };
    }

    const mergedFloors: ReminderSilenceFloors = {
      beforeFirst: Math.max(instrBaseline, reminderGapFloor),
      between: Math.max(instrBaseline, reminderGapFloor),
      afterLast: Math.max(
        instrBaseline,
        outroClip ? MIN_GAP_BEFORE_OUTRO : 0
      ),
    };

    const g = allocateReminderSilencesWithLongTail(
      totalSilence,
      n,
      mergedFloors
    );
    if (g === null) {
      return { items, timelineEndSec, fits: false };
    }

    let t = cursorEnd + g[0]!;
    for (let i = 0; i < n; i++) {
      cursorEnd = pushItem(t, reminderClips[i]!);
      if (i < n - 1) {
        t = cursorEnd + g[i + 1]!;
      }
    }
  }

  if (outroClip) {
    const outroAt = durationSec - SESSION_END_PAD_SEC - outroDur;
    const minStart = cursorEnd + MIN_GAP_BEFORE_OUTRO;
    const start = clamp(
      outroAt,
      minStart,
      durationSec - SESSION_END_PAD_SEC - outroDur
    );
    if (start + 0.001 < minStart) {
      return { items, timelineEndSec, fits: false };
    }
    pushItem(start, outroClip);
  }

  const pad = SESSION_END_PAD_SEC;
  const fits =
    timelineEndSec <= durationSec - pad + 0.001 &&
    items.every((it) => {
      const clip = selected.find((c) => c.clipId === it.clipId);
      if (!clip) return true;
      return it.atSec + clipDurationSec(clip) <= durationSec + 0.5;
    });

  return { items, timelineEndSec, fits };
}

/**
 * Whether the selected clip list fits in durationSec under the same rules as {@link scheduleNfImPlan}.
 */
export function nfImSelectionFits(
  selected: ScheduleClip[],
  durationSec: number,
  moduleId: string
): boolean {
  return scheduleNfImPlan(selected, durationSec, "Asaf", moduleId).fits;
}
