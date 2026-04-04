/**
 * Fractional module composition: builds a second-precision playback timeline
 * from atomic audio clips (intro → instructions → reminders loop).
 *
 * Gap progression starts short and grows per step, capped by duration tier.
 */

import * as functions from "firebase-functions";

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
