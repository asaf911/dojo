/**
 * Fractional module composition: builds a second-precision playback timeline
 * from atomic audio clips using priority-based selection and dynamic gap scaling.
 *
 * Two-phase approach:
 *   Phase 1 — select which clips to include (priority + randomisation; feasibility via nfImSelectionFits)
 *   Phase 2 — NF/IM placement in fractionalTimeline.ts (scheduleNfImPlan)
 *
 * See docs/fractional-module-composition.md for the full design reference.
 * Module framing intros (all fractional types): docs/fractional-module-intro-rule.md
 * Body scan (BS_FRAC): docs/body-scan-tier-composer.md — `composeBodyScanTierPlan` in bodyScanTierPlan.ts.
 */

import * as functions from "firebase-functions";
import * as path from "path";
import * as fs from "fs";
import {
  composeBodyScanTierPlan,
  type BodyScanTierPlanParams,
} from "./bodyScanTierPlan";
import { composePerfectBreathPlan } from "./perfectBreathPlan";
import {
  composeIntroFractionalPlan,
  introWindowSecFromSessionDurationSec,
} from "./introFractionalPlan";
import {
  FRACTIONAL_INTRO_MIN_DURATION_SEC,
  INT_FRAC_PLAN_MAX_DURATION_SEC,
  INT_FRAC_PLAN_MIN_DURATION_SEC,
} from "./fractionalSessionConstants";
import {
  nfImSelectionFits,
  scheduleNfImPlan,
} from "./fractionalTimeline";
import { useFractionalModulesInCatalogsAndAI } from "./deploymentMode";

export { FRACTIONAL_INSTRUCTION_PAIR_GAPS } from "./fractionalTimeline";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export type FractionalClipRole =
  | "intro"
  | "entry"
  | "instruction"
  | "integration"
  | "reminder"
  | "outro";

export interface FractionalClip {
  clipId: string;
  role: FractionalClipRole;
  order: number;
  text: string;
  voices: Record<string, string>;
  /** Measured MP3 length (e.g. from scripts/scanBodyScanDurations.mjs). Falls back to estimate if absent. */
  durationSec?: number;
  priority?: "p0" | "p1" | "p2";
  /** Body scan (BS_FRAC): macro zone 1=head/face/neck, 2=chest/belly/pelvic, 3=legs/feet */
  macroZone?: 1 | 2 | 3;
  bodyTier?: "macro" | "regional" | "micro";
  orderUp?: number;
  orderDown?: number;
  introVariant?: "short" | "long";
  entryScanEnd?: "top" | "bottom";
  entryTier?: "macro" | "regional" | "micro";
  integrationOrder?: number;
  /** INT_FRAC: greeting | arrival | orientation layer (see introFractionalPlan.ts). */
  layer?: "greeting" | "arrival" | "orientation";
}

/** Optional SFX (or second voice) played in parallel with the primary clip at the same session second. */
export interface FractionalParallelClip {
  clipId: string;
  url: string;
  text?: string;
}

export interface FractionalPlanItem {
  atSec: number;
  clipId: string;
  role: string;
  text: string;
  url: string;
  parallel?: FractionalParallelClip;
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

const REMINDER_THRESHOLD_SEC = 120;
const OUTRO_THRESHOLD_SEC = 120;

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

// ---------------------------------------------------------------------------
// Phase 1: Select clips
// ---------------------------------------------------------------------------

const NF_IM_CLIP_ROLES: ReadonlySet<FractionalClipRole> = new Set([
  "intro",
  "instruction",
  "reminder",
  "outro",
]);

function selectClips(
  clips: FractionalClip[],
  durationSec: number,
  atTimelineStart: boolean,
  moduleId: string
): FractionalClip[] {
  const sorted = [...clips]
    .filter((c) => NF_IM_CLIP_ROLES.has(c.role))
    .sort((a, b) => a.order - b.order);

  const intros = sorted.filter((c) => c.role === "intro");
  const instructions = sorted.filter((c) => c.role === "instruction");
  const reminders = sorted.filter((c) => c.role === "reminder");
  const outros = sorted.filter((c) => c.role === "outro");

  const p0 = instructions.filter((c) => c.priority === "p0");
  const p1 = instructions.filter((c) => c.priority === "p1");
  const p2 = instructions.filter((c) => c.priority === "p2");

  const selected: FractionalClip[] = [];

  const includeFramingIntro =
    (durationSec >= FRACTIONAL_INTRO_MIN_DURATION_SEC || atTimelineStart) &&
    intros.length > 0;
  if (includeFramingIntro) {
    selected.push(intros[0]);
  }

  selected.push(...p0);
  selected.push(...shuffle(p1));
  selected.push(...shuffle(p2));

  selected.sort((a, b) => a.order - b.order);

  // Trim instructions that don't fit (never remove P0 or intro)
  while (!nfImSelectionFits(selected, durationSec, moduleId) && selected.length > 1) {
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
  }

  // Determine how many reminders fit alongside the selected instructions
  let reminderCount = 0;
  if (durationSec >= REMINDER_THRESHOLD_SEC && reminders.length > 0) {
    for (let r = 1; r <= reminders.length; r++) {
      const trial = [...selected, ...pickRandom(reminders, r)];
      trial.sort((a, b) => a.order - b.order);
      if (!nfImSelectionFits(trial, durationSec, moduleId)) {
        break;
      }
      reminderCount = r;
    }
    reminderCount = Math.max(1, reminderCount);
  }

  selected.push(...pickRandom(reminders, reminderCount));
  selected.sort((a, b) => a.order - b.order);

  // Safety-net trim in case the combined list still exceeds the budget
  while (!nfImSelectionFits(selected, durationSec, moduleId) && selected.length > 1) {
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
  }

  if (durationSec >= OUTRO_THRESHOLD_SEC && outros.length > 0) {
    selected.push(outros[0]);
    if (!nfImSelectionFits(selected, durationSec, moduleId)) {
      selected.pop();
    }
  }

  return selected;
}

// ---------------------------------------------------------------------------
// Public entry point
// ---------------------------------------------------------------------------

export function composeFractionalPlan(
  clips: FractionalClip[],
  durationSec: number,
  voiceId: string,
  moduleId: string,
  atTimelineStart = false
): FractionalPlan {
  const TAG = "[FractionalComposer]";

  const selected = selectClips(clips, durationSec, atTimelineStart, moduleId);
  const scheduled = scheduleNfImPlan(selected, durationSec, voiceId, moduleId);
  const items: FractionalPlanItem[] = scheduled.items.map((it) => ({ ...it }));
  if (!scheduled.fits) {
    functions.logger.warn(
      `${TAG} schedule reported fits=false moduleId=${moduleId} duration=${durationSec}s — check fractionalTimeline`
    );
  }

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
  BS_FRAC: "body_scan_fractional",
  BS_FRAC_UP: "body_scan_fractional",
  BS_FRAC_DOWN: "body_scan_fractional",
  PB_FRAC: "perfect_breath_fractional",
  INT_FRAC: "intro_fractional",
};

/** Inline expansion defaults for BS_FRAC* (see `docs/body-scan-tier-composer.md`). */
const DEFAULT_BODY_SCAN_EXPAND_PARAMS: Pick<
  BodyScanTierPlanParams,
  "introShort" | "introLong" | "includeEntry"
> = {
  introShort: true,
  introLong: false,
  includeEntry: true,
};

/**
 * Maps catalog cue id → composer `bodyScanDirection`.
 * Product: Down = head→feet → `"up"`; Up = feet→head → `"down"`.
 */
function resolveBodyScanExpandDirection(cueId: string): "up" | "down" {
  if (cueId === "BS_FRAC_DOWN") return "up";
  if (cueId === "BS_FRAC_UP") return "down";
  if (cueId === "BS_FRAC") return Math.random() < 0.5 ? "up" : "down";
  return "up";
}

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

/**
 * Intro (`INT_FRAC`) is a prefix: practice-length is chosen by the user; intro audio is added **before**
 * the practice timeline. Numeric minute triggers are practice-relative (0 = practice start); they become
 * absolute `s{sec}` on the playback clock (introPrefix + minuteIndex * 60).
 */
export function applyPracticeRelativeIntroPrefix(
  cues: ResolvedCue[],
  practiceDurationMinutes: number
): {
  cues: ResolvedCue[];
  practiceDurationSec: number;
  introPrefixSec: number;
  sessionDurationSec: number;
} {
  const practiceDurationSec = practiceDurationMinutes * 60;
  const hasIntroFrac = cues.some(
    (c) =>
      c.id === "INT_FRAC" &&
      (c.trigger === "start" || c.trigger === 0 || c.trigger === "0")
  );
  const introPrefixSec = hasIntroFrac
    ? introWindowSecFromSessionDurationSec(practiceDurationSec)
    : 0;
  const sessionDurationSec = practiceDurationSec + introPrefixSec;

  if (introPrefixSec === 0) {
    return {
      cues: cues.map((c) => ({ ...c })),
      practiceDurationSec,
      introPrefixSec,
      sessionDurationSec,
    };
  }

  const out = cues.map((c) => {
    if (c.id === "INT_FRAC") {
      return { ...c, trigger: "start" as const };
    }
    if (c.trigger === "end") {
      return { ...c };
    }
    if (c.trigger === "start") {
      // INT_FRAC is handled above. Any other `start` is practice 00:00 (after intro prefix).
      return { ...c, trigger: `s${introPrefixSec}` };
    }
    if (typeof c.trigger === "number") {
      const minuteIndex = c.trigger;
      return {
        ...c,
        trigger: `s${introPrefixSec + minuteIndex * 60}`,
      };
    }
    return { ...c };
  });

  return {
    cues: out,
    practiceDurationSec,
    introPrefixSec,
    sessionDurationSec,
  };
}

/** Optional breath SFX (or second layer) played in parallel with the primary cue at the same session second. */
export type ResolvedParallelSfx = {
  id: string;
  name: string;
  url: string;
};

export type ResolvedCue = {
  id: string;
  name: string;
  url: string;
  trigger: string | number;
  durationMinutes?: number | null;
  parallelSfx?: ResolvedParallelSfx;
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
  if (!useFractionalModulesInCatalogsAndAI()) {
    return cues;
  }
  const hasFractional = cues.some((c) => FRACTIONAL_MODULE_MAP[c.id]);
  if (!hasFractional) return cues;

  const {
    cues: workingCues,
    practiceDurationSec,
    sessionDurationSec: durationSec,
  } = applyPracticeRelativeIntroPrefix(cues, durationMinutes);

  const result: ResolvedCue[] = [];
  /** First `*_FRAC` row in this cue list (avoids a second fractional row with a bogus `start` trigger). */
  const firstFractionalCueIndex = workingCues.findIndex((c) =>
    Boolean(FRACTIONAL_MODULE_MAP[c.id])
  );

  for (let i = 0; i < workingCues.length; i++) {
    const cue = workingCues[i];
    let catalogSlug = FRACTIONAL_MODULE_MAP[cue.id];

    if (!catalogSlug) {
      result.push(cue);
      continue;
    }

    const startSec = triggerToSeconds(cue.trigger) ?? 0;
    const hasNonFractionalCueBefore = workingCues
      .slice(0, i)
      .some((c) => !FRACTIONAL_MODULE_MAP[c.id]);
    /** Framing intro only if: meditation truly starts with this block (t=0), it's the first fractional row, and no regular cue precedes it (e.g. another intro or module before IM_FRAC). */
    const atFractModuleTimelineStart =
      startSec === 0 &&
      i === firstFractionalCueIndex &&
      !hasNonFractionalCueBefore;

    let endSec: number;
    if (cue.id === "INT_FRAC") {
      const desiredIntro = introWindowSecFromSessionDurationSec(practiceDurationSec);
      let boundary = durationSec;
      for (let j = i + 1; j < workingCues.length; j++) {
        const nextSec = triggerToSeconds(workingCues[j].trigger);
        if (nextSec !== null && nextSec > startSec) {
          boundary = Math.min(boundary, nextSec);
          break;
        }
      }
      const span = boundary - startSec;
      let introSec = Math.min(
        desiredIntro,
        span,
        INT_FRAC_PLAN_MAX_DURATION_SEC
      );
      if (introSec < INT_FRAC_PLAN_MIN_DURATION_SEC) {
        introSec = Math.min(span, INT_FRAC_PLAN_MAX_DURATION_SEC);
      }
      introSec = Math.max(1, introSec);
      endSec = startSec + introSec;
    } else if (cue.durationMinutes && cue.durationMinutes > 0) {
      endSec = Math.min(startSec + cue.durationMinutes * 60, durationSec);
    } else {
      endSec = durationSec;
      for (let j = i + 1; j < workingCues.length; j++) {
        const nextSec = triggerToSeconds(workingCues[j].trigger);
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

    let bodyScanExpandDir: "up" | "down" | undefined;
    if (
      cue.id === "BS_FRAC" ||
      cue.id === "BS_FRAC_UP" ||
      cue.id === "BS_FRAC_DOWN"
    ) {
      bodyScanExpandDir = resolveBodyScanExpandDirection(cue.id);
      functions.logger.info(
        `${TAG} ${cue.id} window=${windowSec}s catalog=${catalogSlug} dir=${bodyScanExpandDir}`
      );
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

    let plan: FractionalPlan;
    if (
      cue.id === "BS_FRAC" ||
      cue.id === "BS_FRAC_UP" ||
      cue.id === "BS_FRAC_DOWN"
    ) {
      const dir = bodyScanExpandDir ?? resolveBodyScanExpandDirection(cue.id);
      plan = composeBodyScanTierPlan(resolvedClips, {
        durationSec: windowSec,
        bodyScanDirection: dir,
        ...DEFAULT_BODY_SCAN_EXPAND_PARAMS,
        voiceId,
        moduleId: cue.id,
        atTimelineStart: atFractModuleTimelineStart,
      });
    } else if (cue.id === "PB_FRAC") {
      plan = composePerfectBreathPlan(
        resolvedClips,
        windowSec,
        voiceId,
        cue.id,
        atFractModuleTimelineStart
      );
    } else if (cue.id === "INT_FRAC") {
      plan = composeIntroFractionalPlan(resolvedClips, windowSec, voiceId, cue.id, {
        sessionDurationSec: practiceDurationSec,
      });
    } else {
      plan = composeFractionalPlan(
        resolvedClips,
        windowSec,
        voiceId,
        cue.id,
        atFractModuleTimelineStart
      );
    }

    functions.logger.info(
      `${TAG} expanded ${cue.id} at ${startSec}s: window=${windowSec}s items=${plan.items.length} fractIntroAtMedStart=${atFractModuleTimelineStart}`
    );

    for (const item of plan.items) {
      const absoluteSec = startSec + item.atSec;
      const base: ResolvedCue = {
        id: item.clipId,
        name: item.text,
        url: item.url,
        trigger: absoluteSec === 0 ? "start" : `s${absoluteSec}`,
      };
      if (item.parallel?.clipId && item.parallel.url) {
        base.parallelSfx = {
          id: item.parallel.clipId,
          name: item.parallel.text ?? item.parallel.clipId,
          url: item.parallel.url,
        };
      }
      result.push(base);
    }
  }

  return result;
}
