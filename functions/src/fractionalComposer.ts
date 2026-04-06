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
  role: "intro" | "instruction" | "reminder" | "outro";
  order: number;
  text: string;
  voices: Record<string, string>;
  /** Measured MP3 length (e.g. from scripts/scanBodyScanDurations.mjs). Falls back to estimate if absent. */
  durationSec?: number;
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
const OUTRO_THRESHOLD_SEC = 120;

interface GapTier {
  maxDurationSec: number;
  initialGap: number;
  targetGap: number;
  capGap: number;
}

const GAP_TIERS: GapTier[] = [
  { maxDurationSec: 180,  initialGap: 12, targetGap: 35,  capGap: 40  },
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

/**
 * Compute the gap for a given step using linear interpolation.
 * Step 0 returns initialGap, last step returns targetGap, capped at capGap.
 */
function linearGap(
  initialGap: number,
  targetGap: number,
  step: number,
  totalGaps: number,
  capGap: number
): number {
  if (totalGaps <= 1) return Math.min(initialGap, capGap);
  const raw = initialGap + (targetGap - initialGap) * step / (totalGaps - 1);
  return Math.min(raw, capGap);
}

/**
 * Estimate total seconds consumed by `clipCount` clips placed with
 * linearly interpolated gaps from `initialGap` to `targetGap`.
 * Includes a trailing buffer after the last clip.
 */
function estimateTimeline(
  clipCount: number,
  initialGap: number,
  targetGap: number,
  capGap: number
): number {
  let total = 0;
  const totalGaps = clipCount - 1;
  for (let i = 0; i < clipCount; i++) {
    if (i > 0) {
      total += linearGap(initialGap, targetGap, i - 1, totalGaps, capGap);
    }
    total += ESTIMATED_CLIP_SEC;
  }
  if (totalGaps > 0) {
    const lastGap = linearGap(initialGap, targetGap, totalGaps - 1, totalGaps, capGap);
    total += lastGap * TRAILING_BUFFER_FACTOR;
  }
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
  const outros = sorted.filter((c) => c.role === "outro");

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
  let timeline = estimateTimeline(selected.length, tier.initialGap, tier.targetGap, tier.capGap);

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
    timeline = estimateTimeline(selected.length, tier.initialGap, tier.targetGap, tier.capGap);
  }

  // Determine how many reminders fit alongside the selected instructions
  let reminderCount = 0;
  if (durationSec >= REMINDER_THRESHOLD_SEC && reminders.length > 0) {
    const instrCount = selected.length;
    for (let r = 1; r <= reminders.length; r++) {
      const total = instrCount + r;
      const est = estimateTimeline(total, tier.initialGap, tier.targetGap, tier.capGap);
      if (est > durationSec) break;
      reminderCount = r;
    }
    reminderCount = Math.max(1, reminderCount);
  }

  selected.push(...pickRandom(reminders, reminderCount));
  selected.sort((a, b) => a.order - b.order);

  // Safety-net trim in case the combined list still exceeds the budget
  timeline = estimateTimeline(selected.length, tier.initialGap, tier.targetGap, tier.capGap);

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
    timeline = estimateTimeline(selected.length, tier.initialGap, tier.targetGap, tier.capGap);
  }

  if (durationSec >= OUTRO_THRESHOLD_SEC && outros.length > 0) {
    selected.push(outros[0]);
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

  const instrClips = selected.filter(c => c.role === "intro" || c.role === "instruction");
  const reminderClips = selected.filter(c => c.role === "reminder");
  const outroClips = selected.filter(c => c.role === "outro");

  // --- Instruction gaps: tight, with doubling increments ---
  // gap[step] = base + 2^step - 1, capped at 30s
  // base scales modestly from 6s (≤10 min) to 8s (≥20 min)
  const dFactor = Math.min(1, Math.max(0, (durationSec - 600) / 600));
  const instrBase = 6 + 2 * dFactor;
  const INSTR_CAP = 30;

  function instrGapAt(step: number): number {
    return Math.min(instrBase + Math.pow(2, step) - 1, INSTR_CAP);
  }

  const items: FractionalPlanItem[] = [];
  let cursor = 0;

  for (let i = 0; i < instrClips.length; i++) {
    const clip = instrClips[i];
    const url = clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
    if (i === 0) {
      items.push({ atSec: 0, clipId: clip.clipId, role: clip.role, text: clip.text, url });
      cursor = ESTIMATED_CLIP_SEC;
    } else {
      const gap = instrGapAt(i - 1);
      const atSec = cursor + gap;
      items.push({ atSec: Math.round(atSec), clipId: clip.clipId, role: clip.role, text: clip.text, url });
      cursor = atSec + ESTIMATED_CLIP_SEC;
    }
  }

  // --- Reminder gaps: stretch to fill the remaining window ---
  if (reminderClips.length > 0) {
    const n = reminderClips.length;
    const remainingTime = durationSec - cursor;
    const availForGaps = remainingTime - n * ESTIMATED_CLIP_SEC;

    const lastInstrStep = Math.max(0, instrClips.length - 2);
    const remInitial = Math.max(instrGapAt(lastInstrStep), 15);

    let remTarget = remInitial;
    if (n > 1) {
      const denom = n / 2 + TRAILING_BUFFER_FACTOR;
      remTarget = (availForGaps - n * remInitial / 2) / denom;
      remTarget = Math.max(remTarget, remInitial);
    } else {
      remTarget = availForGaps / (1 + TRAILING_BUFFER_FACTOR);
      remTarget = Math.max(remTarget, remInitial);
    }

    for (let i = 0; i < n; i++) {
      const clip = reminderClips[i];
      const url = clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
      const gap = n <= 1 ? remTarget : remInitial + (remTarget - remInitial) * (i / (n - 1));
      const atSec = cursor + gap;
      items.push({ atSec: Math.round(atSec), clipId: clip.clipId, role: clip.role, text: clip.text, url });
      cursor = atSec + ESTIMATED_CLIP_SEC;
    }
  }

  if (outroClips.length > 0) {
    const clip = outroClips[0];
    const url = clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
    const outroAt = Math.max(cursor + ESTIMATED_CLIP_SEC, durationSec - ESTIMATED_CLIP_SEC * 2);
    items.push({ atSec: Math.round(outroAt), clipId: clip.clipId, role: clip.role, text: clip.text, url });
  }

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
  const outroCount = selected.filter((c) => c.role === "outro").length;

  functions.logger.info(
    `${TAG} composed plan=${planId} duration=${durationSec}s total=${items.length} intro=${introCount} instr=${instrCount} rem=${remCount} outro=${outroCount} voice=${voiceId}`
  );

  return { planId, moduleId, durationSec, voiceId, items };
}

// ---------------------------------------------------------------------------
// Body scan (LONG): strict head-to-toe order, no shuffling, dual outro
// ---------------------------------------------------------------------------

const MIN_GAP_BODY_SCAN = 2;
/** Fixed silence: intro → preliminary instruction (C002), and BS_C040 → BS_C041. */
const BODY_SCAN_FIXED_BRIDGE_GAP_SEC = 7;

function bodyScanClipAudioSec(clip: FractionalClip): number {
  if (
    typeof clip.durationSec === "number" &&
    Number.isFinite(clip.durationSec) &&
    clip.durationSec > 0
  ) {
    return clip.durationSec;
  }
  return ESTIMATED_CLIP_SEC;
}

function selectBodyScanLongClips(
  clips: FractionalClip[],
  durationSec: number
): FractionalClip[] {
  const sorted = [...clips].sort((a, b) => a.order - b.order);
  const intros = sorted.filter((c) => c.role === "intro");
  const instructions = sorted
    .filter((c) => c.role === "instruction")
    .sort((a, b) => a.order - b.order);
  const outros = sorted
    .filter((c) => c.role === "outro")
    .sort((a, b) => a.order - b.order);

  if (instructions.length === 0) {
    return [...intros, ...outros];
  }

  const prelim = instructions[0];
  let scanOnly = instructions.slice(1);
  const minScanParts = 4;

  const buildSelected = (): FractionalClip[] => [
    ...intros,
    prelim,
    ...scanOnly,
    ...outros,
  ];

  const minimalDuration = (sel: FractionalClip[]): number => {
    let t = 0;
    for (let i = 0; i < sel.length; i++) {
      if (i > 0) t += MIN_GAP_BODY_SCAN;
      t += bodyScanClipAudioSec(sel[i]);
    }
    return t;
  };

  while (
    scanOnly.length > minScanParts &&
    minimalDuration(buildSelected()) > durationSec
  ) {
    const mid = Math.floor(scanOnly.length / 2);
    scanOnly.splice(mid, 1);
  }

  while (
    scanOnly.length > 0 &&
    minimalDuration(buildSelected()) > durationSec
  ) {
    const mid = Math.floor(scanOnly.length / 2);
    scanOnly.splice(mid, 1);
  }

  let workingIntros = [...intros];
  while (
    workingIntros.length > 0 &&
    minimalDuration([...workingIntros, prelim, ...scanOnly, ...outros]) >
      durationSec
  ) {
    workingIntros = workingIntros.slice(0, -1);
  }

  return [...workingIntros, prelim, ...scanOnly, ...outros];
}

/**
 * Inter-clip gaps + trailing silence after the last clip (through session end).
 *
 * Fixed {@link BODY_SCAN_FIXED_BRIDGE_GAP_SEC}s after:
 * - Intro → preliminary instruction (C002)
 * - BS_C040 → BS_C041
 *
 * All other inter-clip silences (C002 → C003 “top of head” and every body part step,
 * last body part → C040, etc.) share one equal value G. Trailing silence after C041
 * also equals G so the module tail matches body spacing.
 */
function bodyScanGapsAndTrailing(
  all: FractionalClip[],
  durationSec: number
): { between: number[]; trailing: number } {
  const n = all.length;
  if (n === 0) return { between: [], trailing: 0 };

  const audioTotal = all.reduce((sum, c) => sum + bodyScanClipAudioSec(c), 0);
  const gapBudget = Math.max(0, durationSec - audioTotal);

  if (n === 1) {
    const trailing = Math.max(MIN_GAP_BODY_SCAN, gapBudget);
    return { between: [], trailing };
  }

  const fixedBridge = new Set<number>();
  if (all[0].role === "intro") {
    fixedBridge.add(0);
  }
  for (let i = 0; i < n - 1; i++) {
    if (all[i].clipId === "BS_C040" && all[i + 1].clipId === "BS_C041") {
      fixedBridge.add(i);
    }
  }

  const f = fixedBridge.size;
  // (n - 1 - f) inter-clip slots at G, plus 1 trailing slot at G
  const gSlotCount = n - f;
  const fixedSum = f * BODY_SCAN_FIXED_BRIDGE_GAP_SEC;
  let G = gSlotCount > 0 ? (gapBudget - fixedSum) / gSlotCount : MIN_GAP_BODY_SCAN;
  G = Math.max(MIN_GAP_BODY_SCAN, G);

  const between: number[] = [];
  for (let i = 0; i < n - 1; i++) {
    between.push(
      fixedBridge.has(i) ? BODY_SCAN_FIXED_BRIDGE_GAP_SEC : G
    );
  }

  return { between, trailing: G };
}

function placeBodyScanLongTimeline(
  selected: FractionalClip[],
  durationSec: number,
  voiceId: string
): FractionalPlanItem[] {
  const head = selected
    .filter((c) => c.role !== "outro")
    .sort((a, b) => a.order - b.order);
  const outros = selected
    .filter((c) => c.role === "outro")
    .sort((a, b) => a.order - b.order);

  const all = [...head, ...outros];
  const n = all.length;
  if (n === 0) return [];

  const { between } = bodyScanGapsAndTrailing(all, durationSec);

  const items: FractionalPlanItem[] = [];
  // Integer `atSec` matches the timer (`elapsed >= sec`). Next start = round(end of prior clip + gap),
  // not a float cursor that only rounded the label — that drifted silence away from `between[]`.
  let startSec = 0;

  for (let i = 0; i < n; i++) {
    const clip = all[i];
    const url = clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
    items.push({
      atSec: startSec,
      clipId: clip.clipId,
      role: clip.role,
      text: clip.text,
      url,
    });
    const audioSec = bodyScanClipAudioSec(clip);
    const endTime = startSec + audioSec;
    if (i < n - 1) {
      startSec = Math.round(endTime + between[i]);
    }
  }

  return items;
}

/**
 * Body scan LONG: fixed order (catalog order), optional middle trim if duration is tight;
 * always schedules two closing clips when present.
 */
export function composeBodyScanLongPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string
): FractionalPlan {
  const TAG = "[FractionalComposer][BodyScanLong]";

  const selected = selectBodyScanLongClips(clips, durationSec);
  const items = placeBodyScanLongTimeline(selected, durationSec, voiceId);

  const planId = `${moduleId.toLowerCase()}-long-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;

  const introCount = selected.filter((c) => c.role === "intro").length;
  const instrCount = selected.filter((c) => c.role === "instruction").length;
  const outroCount = selected.filter((c) => c.role === "outro").length;

  functions.logger.info(
    `${TAG} plan=${planId} duration=${durationSec}s items=${items.length} intro=${introCount} instr=${instrCount} outro=${outroCount} voice=${voiceId}`
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
  IM_FRAC: "i_am_mantra_fractional",
  BS_FRAC: "body_scan_fractional_long",
};

const BODY_SCAN_LONG_MODULE_IDS = new Set<string>(["BS_FRAC"]);

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

    const plan = BODY_SCAN_LONG_MODULE_IDS.has(cue.id)
      ? composeBodyScanLongPlan(resolvedClips, windowSec, voiceId, cue.id)
      : composeFractionalPlan(resolvedClips, windowSec, voiceId, cue.id);

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
