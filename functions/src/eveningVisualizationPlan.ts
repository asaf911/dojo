/**
 * Evening Visualization (EV_KM_FRAC / EV_GR_FRAC): deterministic sequence —
 * ordered instructions → ordered reminders → ordered outro chain.
 * No random reminder selection (unlike morning viz).
 *
 * Catalog: `evening_visualization_fractional.json` — clips use EVK_* vs EVG_* prefixes per variant.
 */

import * as functions from "firebase-functions";
import type { FractionalClip, FractionalPlan, FractionalPlanItem } from "./fractionalComposer";
import {
  allocateReminderSilencesWithLongTail,
  clipDurationSec,
  instrGapAt,
} from "./fractionalTimeline";
import { FRACTIONAL_FIRST_SPEECH_OFFSET_SEC } from "./fractionalSessionConstants";

const SESSION_END_PAD_SEC = 1;
const MIN_GAP_BEFORE_OUTRO = 8;
const OUTRO_CHAIN_GAP_SEC = 1.5;
const MIN_GAP_BETWEEN_REMINDERS_SEC = 20;

function filterPool(
  clips: FractionalClip[],
  moduleId: "EV_KM_FRAC" | "EV_GR_FRAC"
): FractionalClip[] {
  const prefix = moduleId === "EV_KM_FRAC" ? "EVK_" : "EVG_";
  return clips.filter((c) => c.clipId.startsWith(prefix));
}

function sortByOrder(a: FractionalClip, b: FractionalClip): number {
  return (a.order ?? 0) - (b.order ?? 0);
}

const rankPriority = (p?: string) => (p === "p0" ? 0 : p === "p1" ? 1 : 2);

/**
 * Drop one optional clip from instructions or reminders (never first instruction, never outros).
 * Prefers higher priority rank (p2, p1) then higher order.
 */
function dropOneOptionalClip(
  instructions: FractionalClip[],
  reminders: FractionalClip[]
): { instructions: FractionalClip[]; reminders: FractionalClip[] } | null {
  type Target = { kind: "instruction" | "reminder"; idx: number; rank: number; order: number };
  const candidates: Target[] = [];

  for (let i = 1; i < instructions.length; i++) {
    const c = instructions[i]!;
    candidates.push({
      kind: "instruction",
      idx: i,
      rank: rankPriority(c.priority),
      order: c.order ?? 0,
    });
  }
  for (let i = 0; i < reminders.length; i++) {
    const c = reminders[i]!;
    candidates.push({
      kind: "reminder",
      idx: i,
      rank: rankPriority(c.priority),
      order: c.order ?? 0,
    });
  }

  if (candidates.length === 0) return null;

  candidates.sort((a, b) => {
    if (b.rank !== a.rank) return b.rank - a.rank;
    return b.order - a.order;
  });
  const pick = candidates[0]!;
  if (pick.kind === "instruction") {
    return {
      instructions: instructions.filter((_, j) => j !== pick.idx),
      reminders,
    };
  }
  return {
    instructions,
    reminders: reminders.filter((_, j) => j !== pick.idx),
  };
}

function tryPlaceOrdered(
  scheduleBudgetSec: number,
  instructions: FractionalClip[],
  reminders: FractionalClip[],
  outros: FractionalClip[],
  voiceId: string
): { items: FractionalPlanItem[]; fits: boolean; timelineEndSec: number } {
  const items: FractionalPlanItem[] = [];
  const pushItem = (startFloat: number, clip: FractionalClip): number => {
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

  let cursor = 0;
  const speech = [...instructions];
  for (let i = 0; i < speech.length; i++) {
    if (i === 0) {
      cursor = pushItem(0, speech[i]!);
    } else {
      cursor = pushItem(cursor + instrGapAt(scheduleBudgetSec, i - 1), speech[i]!);
    }
  }

  const outroTotal =
    outros.reduce((s, c) => s + clipDurationSec(c), 0) +
    Math.max(0, outros.length - 1) * OUTRO_CHAIN_GAP_SEC;
  const outroLastEnd = scheduleBudgetSec - SESSION_END_PAD_SEC;
  const outroFirstStart = outroLastEnd - outroTotal;

  if (outros.length > 0 && outroFirstStart < cursor + MIN_GAP_BEFORE_OUTRO - 0.01) {
    return { items: [], fits: false, timelineEndSec: 0 };
  }

  let instrBaseline = instrGapAt(scheduleBudgetSec, 0);
  if (speech.length >= 2) {
    const gaps: number[] = [];
    for (let j = 1; j < speech.length; j++) {
      gaps.push(instrGapAt(scheduleBudgetSec, j - 1));
    }
    instrBaseline = Math.min(...gaps);
  }

  const segmentEnd =
    outros.length > 0
      ? outroFirstStart
      : scheduleBudgetSec - SESSION_END_PAD_SEC;
  const afterLastFloor = outros.length > 0 ? MIN_GAP_BEFORE_OUTRO : 0;

  let tAfterReminders = cursor;

  if (reminders.length > 0) {
    const instrEnd = cursor;
    const sumRem = reminders.reduce((s, c) => s + clipDurationSec(c), 0);
    const totalSilence = segmentEnd - instrEnd - sumRem;
    if (totalSilence < -0.01) {
      return { items: [], fits: false, timelineEndSec: 0 };
    }
    const g = allocateReminderSilencesWithLongTail(totalSilence, reminders.length, {
      beforeFirst: Math.max(instrBaseline, MIN_GAP_BEFORE_OUTRO),
      between: Math.max(instrBaseline, MIN_GAP_BETWEEN_REMINDERS_SEC),
      afterLast: Math.max(instrBaseline, afterLastFloor),
    });
    if (g === null) {
      return { items: [], fits: false, timelineEndSec: 0 };
    }
    let t = instrEnd + g[0]!;
    for (let i = 0; i < reminders.length; i++) {
      t = pushItem(t, reminders[i]!);
      if (i < reminders.length - 1) {
        t += g[i + 1]!;
      }
    }
    tAfterReminders = t;
  }

  let o = outros.length > 0 ? outroFirstStart : tAfterReminders;
  for (let i = 0; i < outros.length; i++) {
    o = pushItem(o, outros[i]!);
    if (i < outros.length - 1) o += OUTRO_CHAIN_GAP_SEC;
  }

  const timelineEndSec = o;
  const allClips = [...speech, ...reminders, ...outros];
  const fits =
    timelineEndSec <= scheduleBudgetSec - SESSION_END_PAD_SEC + 0.5 &&
    items.every((it) => {
      const clip = allClips.find((c) => c.clipId === it.clipId);
      if (!clip) return true;
      return it.atSec + clipDurationSec(clip) <= scheduleBudgetSec + 0.5;
    });

  return { items, fits, timelineEndSec };
}

export function composeEveningVisualizationPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: "EV_KM_FRAC" | "EV_GR_FRAC",
  atTimelineStart: boolean
): FractionalPlan {
  const TAG = "[EveningViz]";
  const scheduleBudgetSec = atTimelineStart
    ? Math.max(1, durationSec - FRACTIONAL_FIRST_SPEECH_OFFSET_SEC)
    : durationSec;

  const pool = filterPool(clips, moduleId);
  const instructionsAll = pool.filter((c) => c.role === "instruction").sort(sortByOrder);
  const remindersAll = pool.filter((c) => c.role === "reminder").sort(sortByOrder);
  const outrosAll = pool.filter((c) => c.role === "outro").sort(sortByOrder);

  let instructions = [...instructionsAll];
  let reminders = [...remindersAll];
  const outros = [...outrosAll];

  let best = tryPlaceOrdered(scheduleBudgetSec, instructions, reminders, outros, voiceId);

  while (!best.fits) {
    const dropped = dropOneOptionalClip(instructions, reminders);
    if (!dropped) break;
    instructions = dropped.instructions;
    reminders = dropped.reminders;
    best = tryPlaceOrdered(scheduleBudgetSec, instructions, reminders, outros, voiceId);
  }

  if (!best.fits) {
    functions.logger.warn(
      `${TAG} fits=false moduleId=${moduleId} duration=${durationSec}s — trying tail-outro fallback`
    );
    for (let k = outros.length; k >= 1; k--) {
      const tailOut = outros.slice(-k);
      for (let n = instructionsAll.length; n >= 0; n--) {
        const instr = n === 0 ? [] : instructionsAll.slice(0, n);
        const res = tryPlaceOrdered(scheduleBudgetSec, instr, [], tailOut, voiceId);
        if (res.fits) {
          best = res;
          break;
        }
      }
      if (best.fits) break;
    }
  }

  if (!best.fits) {
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

export function isEveningVisualizationModuleId(id: string): id is "EV_KM_FRAC" | "EV_GR_FRAC" {
  return id === "EV_KM_FRAC" || id === "EV_GR_FRAC";
}
