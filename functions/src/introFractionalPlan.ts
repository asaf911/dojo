/**
 * Layered Intro fractional module (INT_FRAC).
 * @see docs/intro-fractional-composer.md
 */

import * as functions from "firebase-functions";
import type {
  FractionalClip,
  FractionalPlan,
  FractionalPlanItem,
} from "./fractionalComposer";
import {
  clipDurationSec,
  FRACTIONAL_INSTRUCTION_PAIR_GAPS,
} from "./fractionalTimeline";

const TAG = "[IntroFractionalPlan]";

/** First spoken line starts this many seconds after the module window begins (music at 0). */
export const INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC = 7;

/** Silence after the last clip ends before the next module / block. */
export const INTRO_FRAC_END_PAUSE_SEC = 5;

const MODULE_ID = "INT_FRAC";

type Layer = "greeting" | "arrival" | "orientation";

type GreetingFamily = "morning" | "evening" | "neutral" | "returning";

const GREETING_FAMILY: Record<string, GreetingFamily> = {
  INT_GRT_100: "morning",
  INT_GRT_104: "evening",
  INT_GRT_106: "neutral",
  INT_GRT_108: "returning",
};

function shuffle<T>(arr: T[], rng: () => number): T[] {
  const a = [...arr];
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(rng() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function arrivalsMutuallyCompatible(ids: string[]): boolean {
  const has = (x: string) => ids.includes(x);
  if (has("INT_ARR_120") && has("INT_ARR_122")) return false;
  if (has("INT_ARR_124") && has("INT_ARR_126")) return false;
  return true;
}

function gapBetween(
  from: FractionalClip,
  to: FractionalClip,
  moduleId: string
): number {
  const key = `${from.clipId}|${to.clipId}`;
  const pair = FRACTIONAL_INSTRUCTION_PAIR_GAPS[moduleId]?.[key];
  if (pair != null && Number.isFinite(pair)) return pair;

  const fl = from.layer;
  const tl = to.layer;
  if (fl === "greeting" && tl === "arrival") return 3;
  if (fl === "greeting" && tl === "orientation") return 4;
  if (fl === "arrival" && tl === "arrival") return 4;
  if (fl === "arrival" && tl === "orientation") return 5;
  return 4;
}

function timelineEndSec(sequence: FractionalClip[], moduleId: string): number {
  if (sequence.length === 0) return INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC;

  let t = INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC;
  for (let i = 0; i < sequence.length; i++) {
    const c = sequence[i]!;
    t += clipDurationSec(c);
    if (i < sequence.length - 1) {
      t += gapBetween(c, sequence[i + 1]!, moduleId);
    }
  }
  return t;
}

function fitsBudget(
  sequence: FractionalClip[],
  durationSec: number,
  moduleId: string
): boolean {
  const end = timelineEndSec(sequence, moduleId);
  return end + INTRO_FRAC_END_PAUSE_SEC <= durationSec + 1e-6;
}

function pickGreeting(
  byLayer: Map<Layer, FractionalClip[]>,
  rng: () => number
): FractionalClip | undefined {
  const families: GreetingFamily[] = [
    "morning",
    "evening",
    "neutral",
    "returning",
  ];
  const f = families[Math.floor(rng() * families.length)]!;
  const pool = (byLayer.get("greeting") ?? []).filter(
    (c) => GREETING_FAMILY[c.clipId] === f
  );
  if (pool.length === 0) return undefined;
  return pool[Math.floor(rng() * pool.length)]!;
}

function pickOrientation(
  byLayer: Map<Layer, FractionalClip[]>
): FractionalClip | undefined {
  const o = byLayer.get("orientation") ?? [];
  return o.find((c) => c.clipId === "INT_ORI_140") ?? o[0];
}

function pickArrivalSequence(
  byLayer: Map<Layer, FractionalClip[]>,
  count: 0 | 1 | 2,
  rng: () => number
): FractionalClip[] {
  if (count === 0) return [];
  const arrivals = shuffle(byLayer.get("arrival") ?? [], rng);
  if (count === 1) {
    return arrivals[0] ? [arrivals[0]] : [];
  }
  for (let attempt = 0; attempt < 40; attempt++) {
    const shuffled = shuffle(byLayer.get("arrival") ?? [], rng);
    for (let i = 0; i < shuffled.length; i++) {
      for (let j = i + 1; j < shuffled.length; j++) {
        const a = shuffled[i]!;
        const b = shuffled[j]!;
        if (arrivalsMutuallyCompatible([a.clipId, b.clipId])) {
          return [a, b];
        }
      }
    }
  }
  return arrivals[0] ? [arrivals[0]] : [];
}

type Template = {
  g: boolean;
  a: 0 | 1 | 2;
  o: boolean;
};

/** Try richer openings first, then trim. */
const TEMPLATES: Template[] = [
  { g: true, a: 2, o: true },
  { g: true, a: 1, o: true },
  { g: true, a: 2, o: false },
  { g: false, a: 2, o: true },
  { g: true, a: 1, o: false },
  { g: false, a: 1, o: true },
  { g: true, a: 0, o: true },
  { g: false, a: 2, o: false },
  { g: false, a: 1, o: false },
  { g: true, a: 0, o: false },
  { g: false, a: 0, o: true },
];

function buildSequenceForTemplate(
  tmpl: Template,
  byLayer: Map<Layer, FractionalClip[]>,
  rng: () => number
): FractionalClip[] {
  const out: FractionalClip[] = [];
  if (tmpl.g) {
    const g = pickGreeting(byLayer, rng);
    if (!g) return [];
    out.push(g);
  }
  const arrivals = pickArrivalSequence(byLayer, tmpl.a, rng);
  out.push(...arrivals);
  if (tmpl.o) {
    const ori = pickOrientation(byLayer);
    if (!ori) return [];
    out.push(ori);
  }
  return out;
}

function selectIntroSequence(
  clips: FractionalClip[],
  durationSec: number,
  moduleId: string,
  rng: () => number
): FractionalClip[] {
  const byLayer = new Map<Layer, FractionalClip[]>();
  for (const c of clips) {
    const L = c.layer;
    if (L !== "greeting" && L !== "arrival" && L !== "orientation") continue;
    if (!byLayer.has(L)) byLayer.set(L, []);
    byLayer.get(L)!.push(c);
  }

  for (const tmpl of TEMPLATES) {
    for (let trial = 0; trial < 25; trial++) {
      const seq = buildSequenceForTemplate(tmpl, byLayer, rng);
      if (seq.length === 0) continue;
      if (fitsBudget(seq, durationSec, moduleId)) return seq;
    }
  }

  const ori = pickOrientation(byLayer);
  if (ori && fitsBudget([ori], durationSec, moduleId)) return [ori];

  const arr = byLayer.get("arrival") ?? [];
  for (const c of shuffle(arr, rng)) {
    if (fitsBudget([c], durationSec, moduleId)) return [c];
  }

  const gr = byLayer.get("greeting") ?? [];
  for (const c of shuffle(gr, rng)) {
    if (fitsBudget([c], durationSec, moduleId)) return [c];
  }

  return [];
}

function toPlanItems(
  sequence: FractionalClip[],
  voiceId: string,
  moduleId: string
): FractionalPlanItem[] {
  if (sequence.length === 0) return [];

  let cursor = INTRO_FRAC_FIRST_SPEECH_OFFSET_SEC;
  const items: FractionalPlanItem[] = [];

  for (let i = 0; i < sequence.length; i++) {
    const clip = sequence[i]!;
    const url =
      clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
    items.push({
      atSec: Math.round(cursor),
      clipId: clip.clipId,
      role: clip.role,
      text: clip.text,
      url,
    });
    if (i < sequence.length - 1) {
      cursor += clipDurationSec(clip);
      cursor += gapBetween(clip, sequence[i + 1]!, moduleId);
    }
  }

  return items;
}

/**
 * Builds INT_FRAC timeline: first cue at 7s, layered greeting/arrival/orientation, end padding.
 */
export function composeIntroFractionalPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string = MODULE_ID
): FractionalPlan {
  return composeIntroFractionalPlanWithRng(
    clips,
    durationSec,
    voiceId,
    moduleId,
    Math.random
  );
}

/** @internal Test hook: inject `rng` for deterministic plans. */
export function composeIntroFractionalPlanWithRng(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string,
  rng: () => number
): FractionalPlan {
  const selected = selectIntroSequence(clips, durationSec, moduleId, rng);
  const items = toPlanItems(selected, voiceId, moduleId);

  if (selected.length === 0) {
    functions.logger.warn(
      `${TAG} empty plan durationSec=${durationSec}s — increase window or add clips`
    );
  } else if (!fitsBudget(selected, durationSec, moduleId)) {
    functions.logger.warn(
      `${TAG} schedule overrun moduleId=${moduleId} duration=${durationSec}s`
    );
  }

  const planId = `${moduleId.toLowerCase()}-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;

  functions.logger.info(
    `${TAG} composed plan=${planId} items=${items.length} duration=${durationSec}s voice=${voiceId}`
  );

  return { planId, moduleId, durationSec, voiceId, items };
}
