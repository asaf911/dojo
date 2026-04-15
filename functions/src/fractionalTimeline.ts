/**
 * NF_FRAC / IM_FRAC unified timeline: instruction spacing + monotonic reminder gaps
 * + explicit tail (silence before outro or session end). Selection and placement share this module.
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
/** Cap for each reminder gap in linear ramp. */
const REMINDER_GAP_CAP = 120;
/** Session end padding after last clip (seconds). */
const SESSION_END_PAD_SEC = 1;
/** Minimum gap after last reminder before outro starts. */
const MIN_GAP_BEFORE_OUTRO = 16;

const TAIL_FRAC = 0.24;
/** IM_FRAC: reserve more span for uninterrupted practice after last reminder. */
const IM_TAIL_FRAC = 0.30;
const TAIL_ABS_MIN = 12;
const IM_TAIL_ABS_MIN = 14;
const TAIL_ABS_MAX = 60;

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

function instrGapAt(durationSec: number, step: number): number {
  const dFactor = Math.min(1, Math.max(0, (durationSec - 600) / 600));
  const instrBase = 6 + 2 * dFactor;
  const INSTR_CAP = 30;
  return Math.min(instrBase + Math.pow(2, step) - 1, INSTR_CAP);
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

export interface ScheduleNfImResult {
  items: NfImPlanItem[];
  /** End time of last scheduled clip audio (max start + duration). */
  timelineEndSec: number;
  fits: boolean;
}

/**
 * Build plan items for NF/IM using one schedule: exponential instruction gaps (with pair overrides),
 * then linearly growing reminder gaps and explicit tail.
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

  const lastInstrStep = Math.max(0, instrClips.length - 2);
  const reminderGapFloor =
    moduleId === "IM_FRAC"
      ? IM_REMINDER_GAP_FLOOR
      : moduleId === "NF_FRAC"
        ? NF_REMINDER_GAP_FLOOR
        : REMINDER_GAP_FLOOR;
  const remInitial = Math.max(
    instrGapAt(durationSec, lastInstrStep),
    reminderGapFloor
  );

  const outroClip = outroClips[0];
  const outroDur = outroClip ? clipDurationSec(outroClip) : 0;

  if (reminderClips.length > 0) {
    const n = reminderClips.length;
    const sumRemD = reminderClips.reduce((s, c) => s + clipDurationSec(c), 0);

    let spanEnd: number;
    if (outroClip) {
      const outroAt = durationSec - SESSION_END_PAD_SEC - outroDur;
      spanEnd = outroAt - MIN_GAP_BEFORE_OUTRO;
    } else {
      spanEnd = durationSec - SESSION_END_PAD_SEC;
    }

    const span = spanEnd - cursorEnd;
    if (span <= 0) {
      return { items, timelineEndSec, fits: false };
    }

    const tailFrac = moduleId === "IM_FRAC" ? IM_TAIL_FRAC : TAIL_FRAC;
    const tailAbsMin = moduleId === "IM_FRAC" ? IM_TAIL_ABS_MIN : TAIL_ABS_MIN;

    let tailSec = clamp(
      span * tailFrac,
      tailAbsMin,
      Math.min(TAIL_ABS_MAX, durationSec * 0.30)
    );
    let gapBudget = span - sumRemD - tailSec;

    while (gapBudget < n * remInitial && tailSec > tailAbsMin) {
      tailSec = Math.max(tailAbsMin, tailSec - 4);
      gapBudget = span - sumRemD - tailSec;
    }

    if (gapBudget < 0) {
      return { items, timelineEndSec, fits: false };
    }

    if (n === 1) {
      if (gapBudget < remInitial) {
        return { items, timelineEndSec, fits: false };
      }
      cursorEnd = pushItem(cursorEnd + gapBudget, reminderClips[0]);
    } else {
      const idealLast = (2 * gapBudget) / n - remInitial;
      if (idealLast < remInitial) {
        const uniform = gapBudget / n;
        if (uniform < 8) {
          return { items, timelineEndSec, fits: false };
        }
        for (let i = 0; i < n; i++) {
          cursorEnd = pushItem(cursorEnd + uniform, reminderClips[i]);
        }
      } else {
        let gLast = Math.min(idealLast, REMINDER_GAP_CAP);
        const gaps: number[] = [];
        for (let i = 0; i < n; i++) {
          const t = i / (n - 1);
          gaps.push(remInitial + (gLast - remInitial) * t);
        }
        let sumG = gaps.reduce((a, b) => a + b, 0);
        const scale = gapBudget / sumG;
        for (let i = 0; i < n; i++) {
          gaps[i] *= scale;
        }
        for (let i = 0; i < n; i++) {
          cursorEnd = pushItem(cursorEnd + gaps[i], reminderClips[i]);
        }
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
