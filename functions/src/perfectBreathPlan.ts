/**
 * Deterministic Perfect Breath (PB_FRAC) timeline composer.
 * See docs/perfect-breath-fractional-composer.md.
 */

import * as functions from "firebase-functions";
import type {
  FractionalClip,
  FractionalParallelClip,
  FractionalPlan,
  FractionalPlanItem,
} from "./fractionalComposer"; // type-only: no runtime cycle with fractionalComposer importing this module

const TAG = "[PerfectBreathPlan]";

/** ≤60s: no intro clip; one prep pair; 10s release — fits a 1-minute fractional block. */
const ONE_MINUTE_PB_MAX_SEC = 60;

/**
 * ~3 min fractional PB block (±~15s). Fewer prep rounds, longer down hold, extra quiet after final 320.
 */
const THREE_MIN_PB_MIN_SEC = 165;
const THREE_MIN_PB_MAX_SEC = 200;

/**
 * Quiet after final `320` ends (~3 min band only). At least 10 s to session end (timer keeps running).
 * Kept at the minimum so a second cycle can fit real clip lengths in a 180 s window.
 */
const THREE_MIN_TRAILING_AFTER_FINAL_320_SEC = 10;

function isApproxThreeMinutePB(durationSec: number): boolean {
  return durationSec >= THREE_MIN_PB_MIN_SEC && durationSec <= THREE_MIN_PB_MAX_SEC;
}

function trailingAfterFinal320Sec(durationSec: number): number {
  return isApproxThreeMinutePB(durationSec) ? THREE_MIN_TRAILING_AFTER_FINAL_320_SEC : 0;
}

/** Silence after intro voice (`OPEN`) before first prep inhale (`100`). */
const INTRO_SILENCE_SEC = 4;

/**
 * ~3 min band uses a slightly shorter intro pause than the default so two cycles still fit ~180 s
 * with ≥10 s tail after final `320` (see `betweenCyclesSilenceSec`).
 */
function introSilenceSec(durationSec: number): number {
  return isApproxThreeMinutePB(durationSec) ? 3 : INTRO_SILENCE_SEC;
}

/** Default silence after `322` before the next cycle’s prep (`100`). */
const BETWEEN_CYCLES_SILENCE_SEC = 10;

/** Tighter gap in the ~3 min band so two full cycles fit ~180 s with real narration durations. */
function betweenCyclesSilenceSec(durationSec: number): number {
  return isApproxThreeMinutePB(durationSec) ? 3 : BETWEEN_CYCLES_SILENCE_SEC;
}
const RECOVERY_TOP_HOLD_SEC = 5;
/** Silence after retention inhale ends, before 230 (early in top hold). */
const SILENCE_BEFORE_230_SEC = 2;
/** Silence after 230 ends, before release line. */
const SILENCE_AFTER_230_SEC = 2;

/**
 * Preparation phase timeline is driven by breath SFX (not narration length).
 * Narration starts with the matching SFX; next cue is scheduled after SFX + gap.
 */
const PREP_INHALE_SFX_SEC = 5;
const PREP_GAP_AFTER_INHALE_SEC = 2;
const PREP_EXHALE_SFX_SEC = 5;
const PREP_GAP_AFTER_EXHALE_SEC = 1;
/** Added to both post-inhale and post-exhale gaps for the first prep pair only, each cycle (`100`/`110`). */
const FIRST_PREP_PAIR_EXTRA_GAP_SEC = 1;

const PREP_PAIRS: [string, string][] = [
  ["PBV_BREATH_100", "PBV_BREATH_110"],
  ["PBV_BREATH_120", "PBV_BREATH_130"],
  ["PBV_BREATH_140", "PBV_BREATH_150"],
  ["PBV_BREATH_160", "PBV_BREATH_170"],
];

const ID_OPEN = "PBV_OPEN_000_INTRO_ASAF";
const ID_200 = "PBV_BREATH_200_INHALE_DEEP_AND_HOLD_TOP_ASAF";
const ID_230 = "PBV_BREATH_230_SQUEEZE_AIR_TOP_OF_BELLY_LOWER_LUNGS_ASAF";
const ID_250 = "PBV_HOLD_250_THOUGHTS_ESCAPE_ASAF";

/** Mid-hold “thoughts escape” reminder — skipped for 10s bottom hold (too short). */
function includeMidHoldThoughtsReminder(release: { holdSec: number }): boolean {
  return release.holdSec > 10;
}

/** ~⅓ into the bottom hold (≈30%): 15s→5s, 30s→10s from hold start. */
function midHoldReminderOffsetSec(bottomHoldSec: number): number {
  return Math.max(1, Math.round(bottomHoldSec / 3));
}
const ID_280 = "PBV_BREATH_280_INHALE_RECOVERY_ASAF";
const ID_320 = "PBV_BREATH_320_FINAL_EXHALE_ASAF";
const ID_322 = "PBV_BREATH_322_FINAL_EXHALE_NEXT_CYCLE_ASAF";
const ID_SFX_IN = "PBS_IN";
const ID_SFX_OUT = "PBS_OUT";

const RELEASE_ORDER: { clipId: string; holdSec: number }[] = [
  { clipId: "PBV_BREATH_240_RELEASE_HOLD_10S_ASAF", holdSec: 10 },
  { clipId: "PBV_BREATH_242_RELEASE_HOLD_15S_ASAF", holdSec: 15 },
  { clipId: "PBV_BREATH_244_RELEASE_HOLD_20S_ASAF", holdSec: 20 },
  { clipId: "PBV_BREATH_246_RELEASE_HOLD_25S_ASAF", holdSec: 25 },
  { clipId: "PBV_BREATH_248_RELEASE_HOLD_30S_ASAF", holdSec: 30 },
];

function clipMapFromList(clips: FractionalClip[]): Map<string, FractionalClip> {
  const m = new Map<string, FractionalClip>();
  for (const c of clips) {
    m.set(c.clipId, c);
  }
  return m;
}

function pickUrl(clip: FractionalClip, voiceId: string): string {
  return clip.voices[voiceId] ?? Object.values(clip.voices)[0] ?? "";
}

function clipSec(map: Map<string, FractionalClip>, id: string): number {
  const c = map.get(id);
  const d = c?.durationSec;
  if (typeof d === "number" && Number.isFinite(d) && d > 0) {
    return d;
  }
  functions.logger.warn(`${TAG} missing durationSec for ${id}, using 5s`);
  return 5;
}

/**
 * Integer session second when a voice cue may start, given ideal cursor time.
 * Uses `ceil` so the next cue never shares a second with the tail of the previous clip
 * (timer uses whole-second `elapsed`; `round` could schedule too early vs catalog duration).
 */
function voiceTriggerSec(cursor: number): number {
  const eps = 1e-9;
  return Math.max(0, Math.ceil(cursor - eps));
}

/**
 * Next timeline cursor after a voice cue: scheduled start + catalog duration.
 */
function afterScheduledVoiceCue(
  cursor: number,
  map: Map<string, FractionalClip>,
  voiceClipId: string
): number {
  const atSec = voiceTriggerSec(cursor);
  return atSec + clipSec(map, voiceClipId);
}

/** Cursor after one prep inhale block (SFX window + post-inhale gap). */
function afterPrepInhaleBlock(cursor: number, gapAfterInhaleSec: number): number {
  const atSec = voiceTriggerSec(cursor);
  return atSec + PREP_INHALE_SFX_SEC + gapAfterInhaleSec;
}

/** Cursor after one prep exhale block (SFX window + post-exhale gap). */
function afterPrepExhaleBlock(cursor: number, gapAfterExhaleSec: number): number {
  const atSec = voiceTriggerSec(cursor);
  return atSec + PREP_EXHALE_SFX_SEC + gapAfterExhaleSec;
}

function parallelSfx(
  map: Map<string, FractionalClip>,
  voiceId: string,
  sfxId: string
): FractionalParallelClip {
  const sfx = map.get(sfxId);
  if (!sfx) {
    functions.logger.error(`${TAG} missing SFX clip ${sfxId}`);
    return { clipId: sfxId, url: "", text: "" };
  }
  return {
    clipId: sfxId,
    url: pickUrl(sfx, voiceId),
    text: sfx.text,
  };
}

function pickReleaseForSession(durationSec: number): { clipId: string; holdSec: number } {
  if (durationSec <= ONE_MINUTE_PB_MAX_SEC) return RELEASE_ORDER[0];
  /** ~2 min PB window: 20s bottom hold (not used at ≤60s). */
  if (durationSec <= 120) return RELEASE_ORDER[2];
  /** ~3 min PB: 20s down hold (vs 10s for other 121–240s sessions). */
  if (isApproxThreeMinutePB(durationSec)) return RELEASE_ORDER[2];
  if (durationSec <= 240) return RELEASE_ORDER[0];
  if (durationSec <= 360) return RELEASE_ORDER[1];
  if (durationSec <= 480) return RELEASE_ORDER[2];
  if (durationSec <= 720) return RELEASE_ORDER[3];
  return RELEASE_ORDER[4];
}

function pickPrepPairCount(durationSec: number): number {
  if (durationSec >= 540) return 4;
  if (durationSec >= 300) return 3;
  /** ~3 min: two prep pairs only (100–130), then 200. */
  if (isApproxThreeMinutePB(durationSec)) return 2;
  /** 2–5 min (except ~3 min above): third prep pair (140/150 …). */
  if (durationSec >= 120) return 3;
  if (durationSec <= ONE_MINUTE_PB_MAX_SEC) return 1;
  return 2;
}

function estimateOneCycleSec(
  map: Map<string, FractionalClip>,
  prepPairs: number,
  release: { clipId: string; holdSec: number },
  closingClipId: string
): number {
  let t = 0;
  for (let p = 0; p < prepPairs; p++) {
    const extra = p === 0 ? FIRST_PREP_PAIR_EXTRA_GAP_SEC : 0;
    t = afterPrepInhaleBlock(t, PREP_GAP_AFTER_INHALE_SEC + extra);
    t = afterPrepExhaleBlock(t, PREP_GAP_AFTER_EXHALE_SEC + extra);
  }
  t = afterScheduledVoiceCue(t, map, ID_200);
  t += SILENCE_BEFORE_230_SEC;
  t = afterScheduledVoiceCue(t, map, ID_230);
  t += SILENCE_AFTER_230_SEC;
  t = afterScheduledVoiceCue(t, map, release.clipId);
  const afterRel = t;
  const bottomHold = release.holdSec;
  if (includeMidHoldThoughtsReminder(release)) {
    const hold250At = afterRel + midHoldReminderOffsetSec(bottomHold);
    const at250 = Math.round(hold250At);
    t = Math.max(afterRel + bottomHold, at250 + clipSec(map, ID_250));
  } else {
    t = afterRel + bottomHold;
  }
  t = afterScheduledVoiceCue(t, map, ID_280);
  t += RECOVERY_TOP_HOLD_SEC;
  t = afterScheduledVoiceCue(t, map, closingClipId);
  return t;
}

function estimateSessionSec(
  map: Map<string, FractionalClip>,
  durationSec: number,
  prepPairs: number,
  release: { clipId: string; holdSec: number },
  numCycles: number
): number {
  let t = 0;
  if (durationSec > ONE_MINUTE_PB_MAX_SEC) {
    t = afterScheduledVoiceCue(0, map, ID_OPEN);
    t += introSilenceSec(durationSec);
  }
  for (let i = 0; i < numCycles; i++) {
    const isLast = i === numCycles - 1;
    const closing = isLast ? ID_320 : ID_322;
    t += estimateOneCycleSec(map, prepPairs, release, closing);
    if (!isLast) {
      t += betweenCyclesSilenceSec(durationSec);
    }
  }
  t += trailingAfterFinal320Sec(durationSec);
  return t;
}

function maxCyclesThatFit(
  map: Map<string, FractionalClip>,
  durationSec: number,
  prepPairs: number,
  release: { clipId: string; holdSec: number }
): number {
  for (let k = 20; k >= 1; k--) {
    const est = estimateSessionSec(map, durationSec, prepPairs, release, k);
    if (est <= durationSec + 0.5) {
      return k;
    }
  }
  return 1;
}

function pushVoice(
  items: FractionalPlanItem[],
  cursor: number,
  map: Map<string, FractionalClip>,
  voiceId: string,
  voiceClipId: string,
  role: string,
  parallel?: FractionalParallelClip,
  /** When set, cursor advances by this (e.g. SFX cadence) instead of voice `durationSec`. */
  advanceCursorBySec?: number
): number {
  const clip = map.get(voiceClipId);
  if (!clip) {
    throw new Error(`${TAG} missing catalog clip ${voiceClipId}`);
  }
  const atSec = voiceTriggerSec(cursor);
  items.push({
    atSec,
    clipId: voiceClipId,
    role,
    text: clip.text,
    url: pickUrl(clip, voiceId),
    parallel,
  });
  const advance =
    typeof advanceCursorBySec === "number" &&
    Number.isFinite(advanceCursorBySec) &&
    advanceCursorBySec >= 0
      ? advanceCursorBySec
      : clipSec(map, voiceClipId);
  return atSec + advance;
}

/**
 * Builds a second-precision plan for Perfect Breath.
 */
export function composePerfectBreathPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string
): FractionalPlan {
  const map = clipMapFromList(clips);
  let release = pickReleaseForSession(durationSec);
  let prepPairs = pickPrepPairCount(durationSec);
  let numCycles = maxCyclesThatFit(map, durationSec, prepPairs, release);

  while (
    estimateSessionSec(map, durationSec, prepPairs, release, numCycles) >
    durationSec + 0.5
  ) {
    const idx = RELEASE_ORDER.findIndex((r) => r.clipId === release.clipId);
    if (idx > 0) {
      release = RELEASE_ORDER[idx - 1];
    } else if (prepPairs > 1) {
      prepPairs -= 1;
    } else {
      functions.logger.warn(
        `${TAG} session ${durationSec}s may exceed plan length; using minimal release + prep pairs`
      );
      break;
    }
    numCycles = maxCyclesThatFit(map, durationSec, prepPairs, release);
  }

  const items: FractionalPlanItem[] = [];
  let cursor = 0;

  if (durationSec > ONE_MINUTE_PB_MAX_SEC) {
    cursor = pushVoice(items, cursor, map, voiceId, ID_OPEN, "intro");
    cursor += introSilenceSec(durationSec);
  }

  for (let cycle = 0; cycle < numCycles; cycle++) {
    const isLast = cycle === numCycles - 1;

    for (let p = 0; p < prepPairs; p++) {
      const [inhId, exhId] = PREP_PAIRS[p];
      const extra = p === 0 ? FIRST_PREP_PAIR_EXTRA_GAP_SEC : 0;
      const advanceAfterInhale =
        PREP_INHALE_SFX_SEC + PREP_GAP_AFTER_INHALE_SEC + extra;
      const advanceAfterExhale =
        PREP_EXHALE_SFX_SEC + PREP_GAP_AFTER_EXHALE_SEC + extra;
      cursor = pushVoice(
        items,
        cursor,
        map,
        voiceId,
        inhId,
        "instruction",
        parallelSfx(map, voiceId, ID_SFX_IN),
        advanceAfterInhale
      );
      cursor = pushVoice(
        items,
        cursor,
        map,
        voiceId,
        exhId,
        "instruction",
        parallelSfx(map, voiceId, ID_SFX_OUT),
        advanceAfterExhale
      );
    }

    cursor = pushVoice(
      items,
      cursor,
      map,
      voiceId,
      ID_200,
      "instruction",
      parallelSfx(map, voiceId, ID_SFX_IN)
    );

    cursor += SILENCE_BEFORE_230_SEC;
    cursor = pushVoice(items, cursor, map, voiceId, ID_230, "instruction");
    cursor += SILENCE_AFTER_230_SEC;

    cursor = pushVoice(
      items,
      cursor,
      map,
      voiceId,
      release.clipId,
      "instruction",
      parallelSfx(map, voiceId, ID_SFX_OUT)
    );

    const afterRelease = cursor;
    const bottomHold = release.holdSec;
    if (includeMidHoldThoughtsReminder(release)) {
      const hold250At = afterRelease + midHoldReminderOffsetSec(bottomHold);
      const at250 = Math.round(hold250At);
      const clip250 = map.get(ID_250);
      if (!clip250) {
        throw new Error(`${TAG} missing catalog clip ${ID_250}`);
      }
      items.push({
        atSec: at250,
        clipId: ID_250,
        role: "instruction",
        text: clip250.text,
        url: pickUrl(clip250, voiceId),
      });
      cursor = Math.max(afterRelease + bottomHold, at250 + clipSec(map, ID_250));
    } else {
      cursor = afterRelease + bottomHold;
    }

    cursor = pushVoice(
      items,
      cursor,
      map,
      voiceId,
      ID_280,
      "instruction",
      parallelSfx(map, voiceId, ID_SFX_IN)
    );

    cursor += RECOVERY_TOP_HOLD_SEC;

    const closingId = isLast ? ID_320 : ID_322;
    cursor = pushVoice(
      items,
      cursor,
      map,
      voiceId,
      closingId,
      "outro",
      parallelSfx(map, voiceId, ID_SFX_OUT)
    );

    if (!isLast) {
      cursor += betweenCyclesSilenceSec(durationSec);
    } else {
      cursor += trailingAfterFinal320Sec(durationSec);
    }
  }

  const planId = `${moduleId.toLowerCase()}-${durationSec}s-${voiceId.toLowerCase()}-${Date.now()}`;
  functions.logger.info(
    `${TAG} plan=${planId} cycles=${numCycles} prepPairs=${prepPairs} release=${release.clipId} items=${items.length}`
  );

  return {
    planId,
    moduleId,
    durationSec,
    voiceId,
    items,
  };
}
