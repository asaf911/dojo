/**
 * Morning Visualization (MV_KM_FRAC / MV_GR_FRAC): **orientation** chain (shared room setup,
 * orders 100–120, instruction role) → ordered body instructions → optional reminders → outro.
 * Orientation is not `role: intro`: it always schedules with the module so it still plays when
 * MV is not the first timeline block (no fractional “framing intro” gate).
 *
 * Catalog: `morning_visualization_fractional.json` — clips use MVK_* vs MVG_* prefixes per variant.
 */

import * as functions from "firebase-functions";
import type { FractionalClip, FractionalPlan, FractionalPlanItem } from "./fractionalComposer";
import { clipDurationSec } from "./fractionalTimeline";
import {
  FRACTIONAL_FIRST_SPEECH_OFFSET_SEC,
  FRACTIONAL_INTRO_MIN_DURATION_SEC,
} from "./fractionalSessionConstants";

const SESSION_END_PAD_SEC = 1;
const MIN_GAP_BEFORE_OUTRO = 8;
const OUTRO_CHAIN_GAP_SEC = 1.5;
const REMINDER_THRESHOLD_SEC = 120;

function shuffle<T>(arr: T[]): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function pickRandom<T>(pool: T[], count: number): T[] {
  return shuffle(pool).slice(0, count);
}

/** Matches NF/IM instruction gaps (exponential step). */
function instrGapAt(durationSec: number, step: number): number {
  const dFactor = Math.min(1, Math.max(0, (durationSec - 600) / 600));
  const instrBase = 6 + 2 * dFactor;
  const INSTR_CAP = 30;
  return Math.min(instrBase + Math.pow(2, step) - 1, INSTR_CAP);
}

function filterPool(
  clips: FractionalClip[],
  moduleId: "MV_KM_FRAC" | "MV_GR_FRAC"
): FractionalClip[] {
  const prefix = moduleId === "MV_KM_FRAC" ? "MVK_" : "MVG_";
  return clips.filter((c) => c.clipId.startsWith(prefix));
}

function sortByOrder(a: FractionalClip, b: FractionalClip): number {
  return (a.order ?? 0) - (b.order ?? 0);
}

/** Remove one clip: prefer higher priority number (p2, then p1), then higher order. */
function dropOneInstruction(instr: FractionalClip[]): FractionalClip[] | null {
  if (instr.length <= 1) return null;
  const rank = (p?: string) => (p === "p0" ? 0 : p === "p1" ? 1 : 2);
  let bestIdx = -1;
  let bestRank = -1;
  let bestOrder = -1;
  for (let i = 0; i < instr.length; i++) {
    const r = rank(instr[i].priority);
    const o = instr[i].order ?? 0;
    if (r > bestRank || (r === bestRank && o > bestOrder)) {
      bestRank = r;
      bestOrder = o;
      bestIdx = i;
    }
  }
  if (bestIdx < 0) return null;
  return instr.filter((_, i) => i !== bestIdx);
}

export function composeMorningVisualizationPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: "MV_KM_FRAC" | "MV_GR_FRAC",
  atTimelineStart: boolean
): FractionalPlan {
  const TAG = "[MorningViz]";
  const scheduleBudgetSec = atTimelineStart
    ? Math.max(1, durationSec - FRACTIONAL_FIRST_SPEECH_OFFSET_SEC)
    : durationSec;

  const pool = filterPool(clips, moduleId);
  const introsAll = pool.filter((c) => c.role === "intro").sort(sortByOrder);
  const instructionsAll = pool.filter((c) => c.role === "instruction").sort(sortByOrder);
  const remindersPool = pool.filter((c) => c.role === "reminder").sort(sortByOrder);
  const outrosAll = pool.filter((c) => c.role === "outro").sort(sortByOrder);

  const includeFramingIntro =
    (durationSec >= FRACTIONAL_INTRO_MIN_DURATION_SEC || atTimelineStart) &&
    introsAll.length > 0;

  const maxReminderCount =
    durationSec >= REMINDER_THRESHOLD_SEC ? remindersPool.length : 0;

  const pushFactory = (items: FractionalPlanItem[]) => {
    return (startFloat: number, clip: FractionalClip): number => {
      const url = clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
      items.push({
        atSec: Math.round(startFloat),
        clipId: clip.clipId,
        role: clip.role,
        text: clip.text,
        url,
      });
      return startFloat + clipDurationSec(clip);
    };
  };

  function tryPlace(
    introsSel: FractionalClip[],
    instrSel: FractionalClip[],
    remSel: FractionalClip[],
    outSel: FractionalClip[]
  ): { items: FractionalPlanItem[]; fits: boolean; timelineEndSec: number } {
    const items: FractionalPlanItem[] = [];
    const pushItem = pushFactory(items);

    let cursor = 0;
    const speech = [...introsSel, ...instrSel];
    for (let i = 0; i < speech.length; i++) {
      if (i === 0) {
        cursor = pushItem(0, speech[i]);
      } else {
        cursor = pushItem(cursor + instrGapAt(scheduleBudgetSec, i - 1), speech[i]);
      }
    }

    const outroTotal =
      outSel.reduce((s, c) => s + clipDurationSec(c), 0) +
      Math.max(0, outSel.length - 1) * OUTRO_CHAIN_GAP_SEC;
    const outroLastEnd = scheduleBudgetSec - SESSION_END_PAD_SEC;
    const outroFirstStart = outroLastEnd - outroTotal;

    if (outroFirstStart < cursor + MIN_GAP_BEFORE_OUTRO - 0.01) {
      return { items: [], fits: false, timelineEndSec: 0 };
    }

    const reminderWindowEnd = outroFirstStart - MIN_GAP_BEFORE_OUTRO;
    let t = cursor + MIN_GAP_BEFORE_OUTRO;

    if (remSel.length > 0) {
      const sumRem = remSel.reduce((s, c) => s + clipDurationSec(c), 0);
      const spaceForGaps = reminderWindowEnd - t - sumRem;
      if (spaceForGaps < -0.01) {
        return { items: [], fits: false, timelineEndSec: 0 };
      }
      if (remSel.length > 1) {
        const gapBetween = spaceForGaps / (remSel.length - 1);
        if (gapBetween < 8) {
          return { items: [], fits: false, timelineEndSec: 0 };
        }
        for (let i = 0; i < remSel.length; i++) {
          t = pushItem(t, remSel[i]);
          if (i < remSel.length - 1) t += gapBetween;
        }
      } else {
        t = pushItem(t, remSel[0]);
      }
      if (t > reminderWindowEnd + 0.01) {
        return { items: [], fits: false, timelineEndSec: 0 };
      }
    }

    let o = outroFirstStart;
    for (let i = 0; i < outSel.length; i++) {
      o = pushItem(o, outSel[i]);
      if (i < outSel.length - 1) o += OUTRO_CHAIN_GAP_SEC;
    }

    const timelineEndSec = o;
    const fits =
      timelineEndSec <= scheduleBudgetSec - SESSION_END_PAD_SEC + 0.5 &&
      items.every((it) => {
        const clip = [...speech, ...remSel, ...outSel].find((c) => c.clipId === it.clipId);
        if (!clip) return true;
        return it.atSec + clipDurationSec(clip) <= scheduleBudgetSec + 0.5;
      });

    return { items, fits, timelineEndSec };
  }

  const introVariants: FractionalClip[][] = [];
  if (includeFramingIntro && introsAll.length > 0) {
    for (let k = introsAll.length; k >= 0; k--) {
      introVariants.push(k === 0 ? [] : introsAll.slice(0, k));
    }
  } else {
    introVariants.push([]);
  }

  let best: { items: FractionalPlanItem[]; fits: boolean; timelineEndSec: number } | null =
    null;

  variantLoop: for (const introsSel of introVariants) {
    let instructions = [...instructionsAll];
    outer: while (instructions.length > 0) {
      for (let r = maxReminderCount; r >= 0; r--) {
        const remPick = pickRandom(remindersPool, r).sort(sortByOrder);
        const res = tryPlace(introsSel, instructions, remPick, outrosAll);
        if (res.fits) {
          best = res;
          break variantLoop;
        }
      }
      const trimmed = dropOneInstruction(instructions);
      if (!trimmed) break;
      instructions = trimmed;
    }
  }

  if (!best || !best.fits) {
    functions.logger.warn(
      `${TAG} fits=false moduleId=${moduleId} duration=${durationSec}s — trying tail-outro fallback`
    );
    for (let k = outrosAll.length; k >= 1; k--) {
      const tailOut = outrosAll.slice(-k);
      for (let n = instructionsAll.length; n >= 0; n--) {
        const instr = n === 0 ? [] : instructionsAll.slice(0, n);
        const res = tryPlace([], instr, [], tailOut);
        if (res.fits) {
          best = res;
          break;
        }
      }
      if (best?.fits) break;
    }
  }

  if (!best || !best.fits) {
    functions.logger.warn(
      `${TAG} fits=false moduleId=${moduleId} duration=${durationSec}s — emitting empty plan`
    );
    best = { items: [], fits: false, timelineEndSec: 0 };
  }

  const speechOffset = atTimelineStart ? FRACTIONAL_FIRST_SPEECH_OFFSET_SEC : 0;
  const shiftedItems = best.items.map((it) => ({
    ...it,
    atSec: it.atSec + speechOffset,
  }));

  const planId = `${moduleId.toLowerCase()}-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;

  functions.logger.info(
    `${TAG} plan=${planId} duration=${durationSec}s items=${shiftedItems.length} voice=${voiceId} atTimelineStart=${atTimelineStart}`
  );

  return {
    planId,
    moduleId,
    durationSec,
    voiceId,
    items: shiftedItems,
  };
}

export function isMorningVisualizationModuleId(id: string): id is "MV_KM_FRAC" | "MV_GR_FRAC" {
  return id === "MV_KM_FRAC" || id === "MV_GR_FRAC";
}
