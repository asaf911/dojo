/**
 * Body scan BS_FRAC: per-macro-zone tier (macro | regional | micro),
 * Equal silence between “parts”: body instructions and integration clips (outros) are scheduled
 * the same way—each part is followed by an equal share of the gap budget (including after the last part).
 * Outros are only chosen when the session can afford that full gap treatment (see minVariableSilenceBudget).
 *
 * `bodyScanDirection` **composer** (not product labels): `"up"` = zones head→feet (top to bottom);
 * `"down"` = feet→head (bottom to top). Cue IDs: BS_FRAC_DOWN → `"up"`, BS_FRAC_UP → `"down"`.
 */

import type { FractionalClip, FractionalPlan, FractionalPlanItem } from "./fractionalComposer";

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
}

const ESTIMATED_CLIP_SEC = 5;
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
  const v = style === "short" ? "short" : "long";
  const found = clips.find(
    (c) => c.role === "intro" && c.introVariant === v
  );
  if (!found) {
    throw new Error(`Body scan catalog missing introVariant=${v}`);
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
 * Distribute `totalTarget` seconds across `slotCount` gaps, each in [minG, maxG].
 * If totalTarget exceeds slotCount*maxG, gaps are all maxG and remainder is returned for trailing silence.
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
  const { durationSec, bodyScanDirection, introShort, introLong, includeEntry } =
    params;
  const intros = pickIntroClips(clips, introShort, introLong);
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
        const firstTier = firstZoneTierForDirection(triple, bodyScanDirection);
        const entry = includeEntry
          ? pickEntryClip(clips, bodyScanDirection, firstTier)
          : null;
        if (includeEntry && !entry) {
          continue;
        }

        let bodyList: FractionalClip[];
        if (includeEntry && entry) {
          const stripped = stripEntryAnchorInstruction(
            bodyFull,
            triple,
            bodyScanDirection
          );
          if (!stripped || stripped.length === 0) {
            continue;
          }
          bodyList = stripped;
        } else {
          bodyList = bodyFull;
        }

        if (bodyList.length === 0) {
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
          if (minT <= durationSec) {
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
  const entryResolved = includeEntry
    ? pickEntryClip(
        clips,
        bodyScanDirection,
        firstZoneTierForDirection(best.triple, bodyScanDirection)
      )
    : null;
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

export function composeBodyScanTierPlan(
  clips: FractionalClip[],
  params: BodyScanTierPlanParams
): FractionalPlan {
  const { durationSec, voiceId, moduleId, includeEntry } = params;

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
  const budgetForVariableGaps = Math.max(0, durationSec - fixedNonVar);
  const varGaps = distributeGapsEqual(budgetForVariableGaps, nVar);

  const items: FractionalPlanItem[] = [];
  let t = 0;
  let gi = 0;

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
    if (clip.role === "instruction" && next.role === "instruction") {
      t += takeGap();
      continue;
    }
    if (clip.role === "instruction" && next.role === "integration") {
      t += takeGap();
      continue;
    }
    if (clip.role === "integration" && next.role === "integration") {
      t += takeGap();
      continue;
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
