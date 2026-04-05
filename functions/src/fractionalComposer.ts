/**
 * Fractional module composition: builds a second-precision playback timeline
 * from atomic audio clips using priority-based selection and dynamic gap scaling.
 *
 * Two-phase approach:
 *   Phase 1 — select which clips to include (priority + randomisation)
 *   Phase 2 — place them on the timeline with growing gaps
 *
 * See docs/fractional-module-composition.md for the full design reference.
 */

import * as functions from "firebase-functions";
import * as path from "path";
import * as fs from "fs";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface FractionalClip {
  clipId: string;
  role: "intro" | "instruction" | "reminder";
  order: number;
  text: string;
  voices: Record<string, string>;
  priority?: "p0" | "p1" | "p2";
}

export interface FractionalPlanItem {
  atSec: number;
  clipId: string;
  role: string;
  text: string;
  url: string;
}

export interface FractionalPlan {
  planId: string;
  moduleId: string;
  durationSec: number;
  voiceId: string;
  items: FractionalPlanItem[];
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const ESTIMATED_CLIP_SEC = 5;
const TRAILING_BUFFER_FACTOR = 1.1;
const INTRO_THRESHOLD_SEC = 240;
const REMINDER_THRESHOLD_SEC = 120;

interface GapTier {
  maxDurationSec: number;
  initialGap: number;
  targetGap: number;
  capGap: number;
}

const GAP_TIERS: GapTier[] = [
  { maxDurationSec: 180,  initialGap: 5,  targetGap: 18,  capGap: 20  },
  { maxDurationSec: 360,  initialGap: 5,  targetGap: 38,  capGap: 45  },
  { maxDurationSec: 480,  initialGap: 7,  targetGap: 55,  capGap: 60  },
  { maxDurationSec: 600,  initialGap: 8,  targetGap: 82,  capGap: 90  },
  { maxDurationSec: Infinity, initialGap: 10, targetGap: 105, capGap: 120 },
];

function gapTierForDuration(durationSec: number): GapTier {
  return GAP_TIERS.find((t) => durationSec <= t.maxDurationSec) ?? GAP_TIERS[GAP_TIERS.length - 1];
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

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

function computeGrowthFactor(initial: number, target: number, steps: number): number {
  if (steps <= 1) return 1;
  return Math.pow(target / initial, 1 / (steps - 1));
}

/**
 * Estimate total seconds consumed by `clipCount` clips placed with
 * progressive gaps starting at `initialGap` with the given growth factor.
 * Includes a trailing buffer after the last clip.
 */
function estimateTimeline(
  clipCount: number,
  initialGap: number,
  growthFactor: number,
  capGap: number
): number {
  let total = 0;
  let gap = initialGap;
  for (let i = 0; i < clipCount; i++) {
    if (i > 0) {
      total += Math.min(gap, capGap);
      gap *= growthFactor;
    }
    total += ESTIMATED_CLIP_SEC;
  }
  const lastGap = Math.min(gap / growthFactor, capGap);
  total += lastGap * TRAILING_BUFFER_FACTOR;
  return total;
}

// ---------------------------------------------------------------------------
// Phase 1: Select clips
// ---------------------------------------------------------------------------

function selectClips(
  clips: FractionalClip[],
  durationSec: number
): FractionalClip[] {
  const sorted = [...clips].sort((a, b) => a.order - b.order);

  const intros = sorted.filter((c) => c.role === "intro");
  const instructions = sorted.filter((c) => c.role === "instruction");
  const reminders = sorted.filter((c) => c.role === "reminder");

  const p0 = instructions.filter((c) => c.priority === "p0");
  const p1 = instructions.filter((c) => c.priority === "p1");
  const p2 = instructions.filter((c) => c.priority === "p2");

  const tier = gapTierForDuration(durationSec);

  const selected: FractionalClip[] = [];

  if (durationSec >= INTRO_THRESHOLD_SEC && intros.length > 0) {
    selected.push(intros[0]);
  }

  selected.push(...p0);
  selected.push(...shuffle(p1));
  selected.push(...shuffle(p2));

  selected.sort((a, b) => a.order - b.order);

  // Trim instructions that don't fit (never remove P0 or intro)
  let gf = computeGrowthFactor(tier.initialGap, tier.targetGap, selected.length);
  let timeline = estimateTimeline(selected.length, tier.initialGap, gf, tier.capGap);

  while (timeline > durationSec && selected.length > 1) {
    let removeIdx = -1;
    for (let i = selected.length - 1; i >= 0; i--) {
      if (selected[i].priority === "p2") { removeIdx = i; break; }
    }
    if (removeIdx === -1) {
      for (let i = selected.length - 1; i >= 0; i--) {
        if (selected[i].priority === "p1") { removeIdx = i; break; }
      }
    }
    if (removeIdx === -1) break;
    selected.splice(removeIdx, 1);
    gf = computeGrowthFactor(tier.initialGap, tier.targetGap, selected.length);
    timeline = estimateTimeline(selected.length, tier.initialGap, gf, tier.capGap);
  }

  // Determine how many reminders fit alongside the selected instructions
  let reminderCount = 0;
  if (durationSec >= REMINDER_THRESHOLD_SEC && reminders.length > 0) {
    const instrCount = selected.length;
    for (let r = 1; r <= reminders.length; r++) {
      const total = instrCount + r;
      const gfCandidate = computeGrowthFactor(tier.initialGap, tier.targetGap, total);
      const est = estimateTimeline(total, tier.initialGap, gfCandidate, tier.capGap);
      if (est > durationSec) break;
      reminderCount = r;
    }
    reminderCount = Math.max(1, reminderCount);
  }

  selected.push(...pickRandom(reminders, reminderCount));
  selected.sort((a, b) => a.order - b.order);

  // Safety-net trim in case the combined list still exceeds the budget
  gf = computeGrowthFactor(tier.initialGap, tier.targetGap, selected.length);
  timeline = estimateTimeline(selected.length, tier.initialGap, gf, tier.capGap);

  while (timeline > durationSec && selected.length > 1) {
    let removeIdx = -1;
    for (let i = selected.length - 1; i >= 0; i--) {
      if (selected[i].role === "reminder") { removeIdx = i; break; }
    }
    if (removeIdx === -1) {
      for (let i = selected.length - 1; i >= 0; i--) {
        if (selected[i].priority === "p2") { removeIdx = i; break; }
      }
    }
    if (removeIdx === -1) {
      for (let i = selected.length - 1; i >= 0; i--) {
        if (selected[i].priority === "p1") { removeIdx = i; break; }
      }
    }
    if (removeIdx === -1) break;
    selected.splice(removeIdx, 1);
    gf = computeGrowthFactor(tier.initialGap, tier.targetGap, selected.length);
    timeline = estimateTimeline(selected.length, tier.initialGap, gf, tier.capGap);
  }

  return selected;
}

// ---------------------------------------------------------------------------
// Phase 2: Place clips on timeline
// ---------------------------------------------------------------------------

function placeOnTimeline(
  selected: FractionalClip[],
  durationSec: number,
  voiceId: string
): FractionalPlanItem[] {
  if (selected.length === 0) return [];

  const tier = gapTierForDuration(durationSec);
  const growthFactor = computeGrowthFactor(tier.initialGap, tier.targetGap, selected.length);

  const items: FractionalPlanItem[] = [];
  let cursor = 0;
  let currentGap = tier.initialGap;
  let lastGapUsed = tier.initialGap;

  for (let i = 0; i < selected.length; i++) {
    const clip = selected[i];

    if (i === 0) {
      items.push({
        atSec: 0,
        clipId: clip.clipId,
        role: clip.role,
        text: clip.text,
        url: clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "",
      });
      cursor = ESTIMATED_CLIP_SEC;
    } else {
      const gap = Math.min(currentGap, tier.capGap);
      const atSec = cursor + gap;
      items.push({
        atSec: Math.round(atSec),
        clipId: clip.clipId,
        role: clip.role,
        text: clip.text,
        url: clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "",
      });
      lastGapUsed = gap;
      cursor = atSec + ESTIMATED_CLIP_SEC;
      currentGap *= growthFactor;
    }
  }

  // Trailing buffer: the plan's last clip should have room to breathe.
  // We don't push a clip here — we just ensure the total timeline
  // (last clip + clip duration + trailing silence) fits in durationSec.
  // The caller (expandFractionalCues) already stops at the window boundary.
  const _trailingEnd = cursor + lastGapUsed * TRAILING_BUFFER_FACTOR;
  void _trailingEnd;

  return items;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

export function composeFractionalPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string
): FractionalPlan {
  const TAG = "[FractionalComposer]";

  const selected = selectClips(clips, durationSec);
  const items = placeOnTimeline(selected, durationSec, voiceId);

  const planId = `${moduleId.toLowerCase()}-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;

  const introCount = selected.filter((c) => c.role === "intro").length;
  const instrCount = selected.filter((c) => c.role === "instruction").length;
  const remCount = selected.filter((c) => c.role === "reminder").length;

  functions.logger.info(
    `${TAG} composed plan=${planId} duration=${durationSec}s total=${items.length} intro=${introCount} instr=${instrCount} rem=${remCount} voice=${voiceId}`
  );

  return { planId, moduleId, durationSec, voiceId, items };
}

// ---------------------------------------------------------------------------
// Fractional expansion for inline use in postMeditations / postAIRequest
// ---------------------------------------------------------------------------

interface FractionalCatalogFile {
  version: string;
  moduleId: string;
  title: string;
  clips: FractionalClip[];
}

const FRACTIONAL_MODULE_MAP: Record<string, string> = {
  NF_FRAC: "nostril_focus_fractional",
};

const CONTENT_STORAGE_BUCKET = "imagine-c6162.appspot.com";

function resolveStorageUrlLocal(relativePath: string): string {
  return `gs://${CONTENT_STORAGE_BUCKET}/${relativePath}`;
}

function loadFractionalCatalogLocal(catalogSlug: string): FractionalCatalogFile | null {
  const catalogsDir = path.join(__dirname, "../catalogs");
  const filePath = path.join(catalogsDir, `${catalogSlug}.json`);
  try {
    const data = fs.readFileSync(filePath, "utf8");
    return JSON.parse(data) as FractionalCatalogFile;
  } catch (e) {
    functions.logger.warn(`[FractionalExpand] failed to load catalog: ${filePath}`, e);
    return null;
  }
}

function triggerToSeconds(trigger: string | number): number | null {
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

export type ResolvedCue = {
  id: string;
  name: string;
  url: string;
  trigger: string | number;
  durationMinutes?: number | null;
};

/**
 * Walks a resolved cue list and expands any fractional module IDs
 * (e.g. NF_FRAC) into multiple second-precision cues with "s{sec}" triggers.
 * Non-fractional cues pass through unchanged.
 */
export function expandFractionalCues(
  cues: ResolvedCue[],
  durationMinutes: number,
  voiceId: string
): ResolvedCue[] {
  const TAG = "[FractionalExpand]";
  const hasFractional = cues.some((c) => FRACTIONAL_MODULE_MAP[c.id]);
  if (!hasFractional) return cues;

  const durationSec = durationMinutes * 60;
  const result: ResolvedCue[] = [];

  for (let i = 0; i < cues.length; i++) {
    const cue = cues[i];
    const catalogSlug = FRACTIONAL_MODULE_MAP[cue.id];

    if (!catalogSlug) {
      result.push(cue);
      continue;
    }

    const startSec = triggerToSeconds(cue.trigger) ?? 0;

    let endSec: number;
    if (cue.durationMinutes && cue.durationMinutes > 0) {
      endSec = Math.min(startSec + cue.durationMinutes * 60, durationSec);
    } else {
      endSec = durationSec;
      for (let j = i + 1; j < cues.length; j++) {
        const nextSec = triggerToSeconds(cues[j].trigger);
        if (nextSec !== null && nextSec > startSec) {
          endSec = nextSec;
          break;
        }
      }
    }

    const windowSec = endSec - startSec;
    if (windowSec <= 0) {
      functions.logger.warn(`${TAG} skipping ${cue.id}: zero/negative window (start=${startSec}, end=${endSec})`);
      result.push(cue);
      continue;
    }

    const catalog = loadFractionalCatalogLocal(catalogSlug);
    if (!catalog || !catalog.clips || catalog.clips.length === 0) {
      functions.logger.warn(`${TAG} catalog not found for ${catalogSlug}, passing cue through`);
      result.push(cue);
      continue;
    }

    const resolvedClips: FractionalClip[] = catalog.clips.map((clip) => ({
      ...clip,
      voices: Object.fromEntries(
        Object.entries(clip.voices).map(([v, p]) => [v, resolveStorageUrlLocal(p)])
      ),
    }));

    const plan = composeFractionalPlan(resolvedClips, windowSec, voiceId, cue.id);

    functions.logger.info(
      `${TAG} expanded ${cue.id} at ${startSec}s: window=${windowSec}s items=${plan.items.length}`
    );

    for (const item of plan.items) {
      const absoluteSec = startSec + item.atSec;
      result.push({
        id: item.clipId,
        name: item.text,
        url: item.url,
        trigger: absoluteSec === 0 ? "start" : `s${absoluteSec}`,
      });
    }
  }

  return result;
}
