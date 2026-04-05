/**
 * Fractional module composition: builds a second-precision playback timeline
 * from atomic audio clips (intro → instructions → reminders loop).
 *
 * Gap progression starts short and grows per step, capped by duration tier.
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

const ESTIMATED_CLIP_DURATION_SEC = 5;
const END_BUFFER_SEC = 5;
const INITIAL_GAP_SEC = 5;
const GAP_GROWTH_FACTOR = 1.3;

function maxGapForDuration(durationSec: number): number {
  if (durationSec <= 180) return 20;
  if (durationSec <= 420) return 45;
  return 75;
}

// ---------------------------------------------------------------------------
// Composer
// ---------------------------------------------------------------------------

export function composeFractionalPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string
): FractionalPlan {
  const TAG = "[FractionalComposer]";
  const sorted = [...clips].sort((a, b) => a.order - b.order);

  const intros = sorted.filter((c) => c.role === "intro");
  const instructions = sorted.filter((c) => c.role === "instruction");
  const reminders = sorted.filter((c) => c.role === "reminder");

  const items: FractionalPlanItem[] = [];
  const maxGap = maxGapForDuration(durationSec);
  const deadline = durationSec - END_BUFFER_SEC;
  let cursor = 0;
  let gap = INITIAL_GAP_SEC;

  function resolveUrl(clip: FractionalClip): string {
    return clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
  }

  function push(clip: FractionalClip, atSec: number): void {
    items.push({
      atSec: Math.round(atSec),
      clipId: clip.clipId,
      role: clip.role,
      text: clip.text,
      url: resolveUrl(clip),
    });
  }

  function wouldExceedDeadline(atSec: number): boolean {
    return atSec + ESTIMATED_CLIP_DURATION_SEC > deadline;
  }

  function advanceGap(): number {
    const current = gap;
    gap = Math.min(maxGap, gap * GAP_GROWTH_FACTOR);
    return current;
  }

  // 1. Intro at t=0
  if (intros.length > 0) {
    push(intros[0], 0);
    cursor = ESTIMATED_CLIP_DURATION_SEC;
  }

  // 2. Instructions in order
  for (const clip of instructions) {
    const nextAt = cursor + advanceGap();
    if (wouldExceedDeadline(nextAt)) break;
    push(clip, nextAt);
    cursor = nextAt + ESTIMATED_CLIP_DURATION_SEC;
  }

  // 3. Reminders loop until budget exhausted
  let reminderIdx = 0;
  let lastClipId: string | null = null;
  while (reminders.length > 0) {
    const nextAt = cursor + advanceGap();
    if (wouldExceedDeadline(nextAt)) break;

    let clip = reminders[reminderIdx % reminders.length];
    // Avoid immediate repeat of same clip
    if (clip.clipId === lastClipId && reminders.length > 1) {
      reminderIdx++;
      clip = reminders[reminderIdx % reminders.length];
    }

    push(clip, nextAt);
    lastClipId = clip.clipId;
    cursor = nextAt + ESTIMATED_CLIP_DURATION_SEC;
    reminderIdx++;
  }

  const planId = `${moduleId.toLowerCase()}-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;

  functions.logger.info(
    `${TAG} composed plan=${planId} duration=${durationSec}s items=${items.length} voice=${voiceId}`
  );

  return {
    planId,
    moduleId,
    durationSec,
    voiceId,
    items,
  };
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
      endSec = Math.min(startSec + cue.durationMinutes * 60, durationSec - END_BUFFER_SEC);
    } else {
      endSec = durationSec - END_BUFFER_SEC;
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
