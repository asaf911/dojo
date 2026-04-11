/**
 * @fileoverview Tier-based body scan composer for `body_scan_fractional.json` (module BS_FRAC / BS_FRAC_*).
 *
 * **Handoff:** Read `docs/body-scan-tier-composer.md` first (product vs composer direction, API, expansion).
 * Module intro policy: `docs/fractional-module-intro-rule.md`.
 *
 * **Pipeline**
 * 1. `chooseBodyScanPlan` — pick per-zone tiers (macro|regional|micro)³, integration count (0–2), and strip
 *    the first scanned instruction when using an ENTRY clip (`stripEntryAnchorInstruction`).
 * 2. `composeBodyScanTierPlan` — build timeline: intros → optional entry → body → integrations; bridges after
 *    each intro/entry; equal silence after each instruction/integration (including after the last part).
 *
 * **Constants** — `ESTIMATED_CLIP_SEC` used when catalog omits `durationSec`; `BODY_GAP_MIN` for feasibility only
 * (actual gaps use the full remaining budget via `distributeGapsEqual`).
 */

import type { FractionalClip, FractionalPlan, FractionalPlanItem } from "./fractionalComposer";
import {
  FRACTIONAL_FIRST_SPEECH_OFFSET_SEC,
  FRACTIONAL_INTRO_MIN_DURATION_SEC,
} from "./fractionalSessionConstants";

export type BodyTier = "macro" | "regional" | "micro";
export type BodyScanDirection = "up" | "down";
export type IntroStyle = "short" | "long";

export interface BodyScanTierPlanParams {
  durationSec: number;
  bodyScanDirection: BodyScanDirection;
  /** Opening line “We will now begin a body scan” */
  introShort: boolean;
  /** Long guidance clip; may be combined with short (short first, then long) */
  introLong: boolean;
  includeEntry: boolean;
  voiceId: string;
  moduleId: string;
  /**
   * When true, module framing intros are allowed even when `durationSec` is under
   * `FRACTIONAL_INTRO_MIN_DURATION_SEC` (fractional block starts at session second 0).
   */
  atTimelineStart?: boolean;
}

const ESTIMATED_CLIP_SEC = 5;
/** Silence between body-scan intro / entry segments (not the global first-speech offset). */
const BRIDGE_SEC = 7;
const BODY_GAP_MIN = 15;

function clipAudioSec(clip: FractionalClip): number {
  const d = clip.durationSec;
  if (typeof d === "number" && Number.isFinite(d) && d > 0) return d;
  return ESTIMATED_CLIP_SEC;
}

function tierRank(t: BodyTier): number {
  return t === "macro" ? 0 : t === "regional" ? 1 : 2;
}

/** Ordered body instructions for one triple and direction (before entry skip). */
export function collectBodyInstructions(
  clips: FractionalClip[],
  triple: readonly [BodyTier, BodyTier, BodyTier],
  direction: BodyScanDirection
): FractionalClip[] {
  const zoneOrder = direction === "up" ? [1, 2, 3] : [3, 2, 1];
  const out: FractionalClip[] = [];
  for (const z of zoneOrder) {
    const tier = triple[z - 1];
    const tierClips = clips.filter(
      (c) =>
        c.role === "instruction" &&
        c.macroZone === z &&
        c.bodyTier === tier
    );
    tierClips.sort((a, b) => {
      const va = direction === "up" ? (a.orderUp ?? 0) : (a.orderDown ?? 0);
      const vb = direction === "up" ? (b.orderUp ?? 0) : (b.orderDown ?? 0);
      return va - vb;
    });
    out.push(...tierClips);
  }
  return out;
}

export function firstZoneTierForDirection(
  triple: readonly [BodyTier, BodyTier, BodyTier],
  direction: BodyScanDirection
): BodyTier {
  return direction === "up" ? triple[0] : triple[2];
}

export function pickEntryClip(
  clips: FractionalClip[],
  direction: BodyScanDirection,
  firstTier: BodyTier
): FractionalClip | null {
  const end = direction === "up" ? "top" : "bottom";
  return (
    clips.find(
      (c) =>
        c.role === "entry" &&
        c.entryScanEnd === end &&
        c.entryTier === firstTier
    ) ?? null
  );
}

/**
 * Remove the first instruction for the first scanned macro zone that matches the entry tier
 * (same anchor the ENTRY_* clip replaces, e.g. micro “top of head” → BS_SYS_060 not BS_MIC_300).
 */
export function stripEntryAnchorInstruction(
  bodyFull: FractionalClip[],
  triple: readonly [BodyTier, BodyTier, BodyTier],
  direction: BodyScanDirection
): FractionalClip[] | null {
  const firstZone = direction === "up" ? 1 : 3;
  const firstTier = firstZoneTierForDirection(triple, direction);
  const idx = bodyFull.findIndex(
    (c) =>
      c.role === "instruction" &&
      c.macroZone === firstZone &&
      c.bodyTier === firstTier
  );
  if (idx < 0) return null;
  return [...bodyFull.slice(0, idx), ...bodyFull.slice(idx + 1)];
}

export function pickIntroClip(
  clips: FractionalClip[],
  style: IntroStyle
): FractionalClip {
  const found = clips.find(
    (c) => c.role === "intro" && c.introVariant === style
  );
  if (!found) {
    throw new Error(`Body scan catalog missing introVariant=${style}`);
  }
  return found;
}

/** Short first, then long when both are requested. At least one flag must be true. */
export function pickIntroClips(
  clips: FractionalClip[],
  includeShort: boolean,
  includeLong: boolean
): FractionalClip[] {
  if (!includeShort && !includeLong) {
    throw new Error("pickIntroClips: at least one of introShort or introLong must be true");
  }
  const out: FractionalClip[] = [];
  if (includeShort) out.push(pickIntroClip(clips, "short"));
  if (includeLong) out.push(pickIntroClip(clips, "long"));
  return out;
}

export function integrationClipsSorted(clips: FractionalClip[]): FractionalClip[] {
  return clips
    .filter((c) => c.role === "integration")
    .sort(
      (a, b) =>
        (a.integrationOrder ?? 0) - (b.integrationOrder ?? 0)
    );
}

/**
 * Split `total` into `n` non‑negative integers as evenly as possible (sum equals `total`).
 * Used for body-scan silence so every pause (including after the last part) gets the same budget.
 */
export function distributeGapsEqual(total: number, n: number): number[] {
  if (n === 0) return [];
  if (total < 0 || !Number.isFinite(total)) {
    throw new Error("distributeGapsEqual: total must be a finite number >= 0");
  }
  const t = Math.floor(total);
  const base = Math.floor(t / n);
  const rem = t - base * n;
  return Array.from({ length: n }, (_, i) => base + (i < rem ? 1 : 0));
}

/**
 * Bounded gap distribution (tests + potential reuse). The tier composer uses `distributeGapsEqual` only.
 */
export function distributeGapsBetweenBounds(
  slotCount: number,
  totalTarget: number,
  minG: number,
  maxG: number
): { gaps: number[]; trailingFromGaps: number } {
  if (slotCount === 0) {
    return { gaps: [], trailingFromGaps: Math.max(0, totalTarget) };
  }
  const minSum = slotCount * minG;
  const maxSum = slotCount * maxG;
  if (totalTarget < minSum) {
    throw new Error(
      `Gap budget infeasible: need >=${minSum}s for ${slotCount} slots, got ${totalTarget}`
    );
  }
  if (totalTarget >= maxSum) {
    return {
      gaps: Array(slotCount).fill(maxG),
      trailingFromGaps: totalTarget - maxSum,
    };
  }
  const extra = totalTarget - minSum;
  const gaps = Array(slotCount).fill(minG);
  let placed = 0;
  let slot = 0;
  while (placed < extra) {
    if (gaps[slot % slotCount] < maxG) {
      gaps[slot % slotCount]++;
      placed++;
    }
    slot++;
    if (slot > slotCount * (maxG - minG + extra + 5)) {
      throw new Error("distributeGapsBetweenBounds: failed to place extra");
    }
  }
  return { gaps, trailingFromGaps: 0 };
}

interface FeasibleChoice {
  triple: [BodyTier, BodyTier, BodyTier];
  kIntegration: number;
  bodyList: FractionalClip[];
  minTotal: number;
  tierScore: number;
  nBody: number;
}

/** Entry clip for this triple/direction, or null if `includeEntry` is false. */
function entryForTriple(
  clips: FractionalClip[],
  direction: BodyScanDirection,
  triple: readonly [BodyTier, BodyTier, BodyTier],
  includeEntry: boolean
): FractionalClip | null {
  if (!includeEntry) return null;
  return pickEntryClip(
    clips,
    direction,
    firstZoneTierForDirection(triple, direction)
  );
}

/**
 * When `entry` is set, remove the first instruction in the first scanned zone for that tier
 * (catalog ENTRY_* replaces that anchor). Otherwise return `bodyFull` unchanged.
 */
function bodyInstructionsWithEntryApplied(
  bodyFull: FractionalClip[],
  triple: readonly [BodyTier, BodyTier, BodyTier],
  direction: BodyScanDirection,
  entry: FractionalClip | null
): FractionalClip[] | null {
  if (!entry) return bodyFull;
  const stripped = stripEntryAnchorInstruction(bodyFull, triple, direction);
  if (!stripped || stripped.length === 0) return null;
  return stripped;
}

/** One bridge after each intro clip, plus one after entry when present. */
function bridgesSec(introCount: number, includeEntry: boolean): number {
  return (introCount + (includeEntry ? 1 : 0)) * BRIDGE_SEC;
}

/**
 * Variable silence slots: one after each “part” (body instruction or integration/outro), same pool, equal split.
 * Slot count = nBody + kIntegration (e.g. 3 zones + 2 outros ⇒ 5 gaps).
 */
export function variableGapSlotCount(
  nBody: number,
  kIntegration: number
): number {
  return nBody + kIntegration;
}

/**
 * Minimum total silence required before we accept a plan. With kIntegration === 0 we keep the looser
 * floor (only between-body minimums; trailing slot shares that budget). With any outro, every part
 * must support the same gap standard: (nBody + kIntegration) slots each at least BODY_GAP_MIN.
 */
export function minVariableSilenceBudget(
  nBody: number,
  kIntegration: number
): number {
  if (kIntegration === 0) {
    return Math.max(0, nBody - 1) * BODY_GAP_MIN;
  }
  return (nBody + kIntegration) * BODY_GAP_MIN;
}

function computeMinTotal(
  intros: FractionalClip[],
  entry: FractionalClip | null,
  includeEntry: boolean,
  bodyList: FractionalClip[],
  kIntegration: number,
  integrationList: FractionalClip[]
): number {
  const nB = bodyList.length;
  if (nB === 0) return Infinity;

  let audio = intros.reduce((s, c) => s + clipAudioSec(c), 0);
  audio +=
    (includeEntry && entry ? clipAudioSec(entry) : 0) +
    bodyList.reduce((s, c) => s + clipAudioSec(c), 0);
  for (let i = 0; i < kIntegration; i++) {
    audio += clipAudioSec(integrationList[i]);
  }

  const b = bridgesSec(intros.length, Boolean(includeEntry && entry));
  const vMin = minVariableSilenceBudget(nB, kIntegration);
  return audio + b + vMin;
}

/** Feasible (duration, tiers, integration count); prefers more integrations then finer tiers. */
export function chooseBodyScanPlan(
  clips: FractionalClip[],
  params: BodyScanTierPlanParams
): {
  triple: [BodyTier, BodyTier, BodyTier];
  kIntegration: number;
  intros: FractionalClip[];
  entry: FractionalClip | null;
  bodyInstructions: FractionalClip[];
  integrations: FractionalClip[];
} {
  const {
    durationSec,
    bodyScanDirection,
    introShort,
    introLong,
    includeEntry,
    atTimelineStart = false,
  } = params;
  const framingIntroAllowed =
    durationSec >= FRACTIONAL_INTRO_MIN_DURATION_SEC || atTimelineStart;
  const fitSec = atTimelineStart
    ? Math.max(1, durationSec - FRACTIONAL_FIRST_SPEECH_OFFSET_SEC)
    : durationSec;
  const useIntroShort = framingIntroAllowed && introShort;
  const useIntroLong = framingIntroAllowed && introLong;
  const intros =
    useIntroShort || useIntroLong
      ? pickIntroClips(clips, useIntroShort, useIntroLong)
      : [];
  const allInt = integrationClipsSorted(clips);

  const tiers: BodyTier[] = ["macro", "regional", "micro"];
  const feasible: FeasibleChoice[] = [];

  for (const t1 of tiers) {
    for (const t2 of tiers) {
      for (const t3 of tiers) {
        const triple = [t1, t2, t3] as [BodyTier, BodyTier, BodyTier];
        const bodyFull = collectBodyInstructions(
          clips,
          triple,
          bodyScanDirection
        );
        const entry = entryForTriple(
          clips,
          bodyScanDirection,
          triple,
          includeEntry
        );
        if (includeEntry && !entry) {
          continue;
        }

        const bodyList = bodyInstructionsWithEntryApplied(
          bodyFull,
          triple,
          bodyScanDirection,
          entry
        );
        if (!bodyList || bodyList.length === 0) {
          continue;
        }

        const tierScore = tierRank(t1) + tierRank(t2) + tierRank(t3);
        const nB = bodyList.length;

        for (let k = 2; k >= 0; k--) {
          const minT = computeMinTotal(
            intros,
            entry,
            Boolean(includeEntry && entry),
            bodyList,
            k,
            allInt
          );
          if (minT <= fitSec) {
            feasible.push({
              triple,
              kIntegration: k,
              bodyList: [...bodyList],
              minTotal: minT,
              tierScore,
              nBody: nB,
            });
            break;
          }
        }
      }
    }
  }

  if (feasible.length === 0) {
    throw new Error(
      "No feasible body scan plan for durationSec; try a longer session (minimum uses all-macro tiers)."
    );
  }

  feasible.sort((a, b) => {
    if (b.kIntegration !== a.kIntegration) return b.kIntegration - a.kIntegration;
    if (b.tierScore !== a.tierScore) return b.tierScore - a.tierScore;
    if (b.nBody !== a.nBody) return b.nBody - a.nBody;
    const lex = (tr: [BodyTier, BodyTier, BodyTier]) =>
      `${tr[0]},${tr[1]},${tr[2]}`;
    return lex(a.triple).localeCompare(lex(b.triple));
  });

  const best = feasible[0];
  const entryResolved = entryForTriple(
    clips,
    bodyScanDirection,
    best.triple,
    includeEntry
  );
  if (includeEntry && !entryResolved) {
    throw new Error("includeEntry true but no matching entry clip in catalog");
  }

  const integrations = allInt.slice(0, best.kIntegration);

  return {
    triple: best.triple,
    kIntegration: best.kIntegration,
    intros,
    entry: entryResolved,
    bodyInstructions: best.bodyList,
    integrations,
  };
}

function voiceUrl(clip: FractionalClip, voiceId: string): string {
  return clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
}

/** Build `FractionalPlan.items` from `chooseBodyScanPlan` + timeline rules (bridges + equal gaps). */
export function composeBodyScanTierPlan(
  clips: FractionalClip[],
  params: BodyScanTierPlanParams
): FractionalPlan {
  const { durationSec, voiceId, moduleId, includeEntry, atTimelineStart } =
    params;
  const leadInSec = atTimelineStart ? FRACTIONAL_FIRST_SPEECH_OFFSET_SEC : 0;

  const choice = chooseBodyScanPlan(clips, params);
  const { intros, entry, bodyInstructions, integrations } = choice;

  const sequence: FractionalClip[] = [...intros];
  if (includeEntry && entry) sequence.push(entry);
  sequence.push(...bodyInstructions);
  sequence.push(...integrations);

  const nB = bodyInstructions.length;
  const kI = integrations.length;

  const audioTotal = sequence.reduce((s, c) => s + clipAudioSec(c), 0);
  const bridges = bridgesSec(intros.length, Boolean(includeEntry && entry));
  const nVar = variableGapSlotCount(nB, kI);
  const fixedNonVar = audioTotal + bridges;
  const budgetForVariableGaps = Math.max(
    0,
    durationSec - leadInSec - fixedNonVar
  );
  const varGaps = distributeGapsEqual(budgetForVariableGaps, nVar);

  const items: FractionalPlanItem[] = [];
  let t = leadInSec;
  let gi = 0;
  const gapBetweenPartsRole = new Set(["instruction", "integration"]);

  const takeGap = (): number => {
    if (gi >= varGaps.length) {
      throw new Error("Body scan gap index overflow");
    }
    return varGaps[gi++];
  };

  for (let i = 0; i < sequence.length; i++) {
    const clip = sequence[i];
    items.push({
      atSec: Math.round(t),
      clipId: clip.clipId,
      role: clip.role,
      text: clip.text,
      url: voiceUrl(clip, voiceId),
    });
    t += clipAudioSec(clip);
    if (i === sequence.length - 1) {
      const isPart =
        clip.role === "instruction" || clip.role === "integration";
      if (isPart && nVar > 0) {
        t += takeGap();
      }
      break;
    }

    const next = sequence[i + 1];

    if (clip.role === "intro") {
      t += BRIDGE_SEC;
      continue;
    }
    if (clip.role === "entry") {
      t += BRIDGE_SEC;
      continue;
    }
    if (gapBetweenPartsRole.has(clip.role) && gapBetweenPartsRole.has(next.role)) {
      t += takeGap();
    }
  }

  if (gi !== varGaps.length) {
    throw new Error(
      `Body scan gap mismatch: consumed ${gi} gaps, expected ${varGaps.length}`
    );
  }

  const planId = `${moduleId.toLowerCase()}-tier-${params.bodyScanDirection}-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;

  return {
    planId,
    moduleId,
    durationSec,
    voiceId,
    items,
  };
}
