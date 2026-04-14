/**
 * @see ../../docs/fractional-module-intro-rule.md — single product reference for all fractional modules.
 */
export const FRACTIONAL_INTRO_MIN_DURATION_SEC = 300;

/**
 * When `atTimelineStart` is true, first spoken voice cue in NF/IM, body scan, and Perfect Breath
 * is scheduled this many seconds after the fractional block begins (same as INT_FRAC first speech).
 */
export const FRACTIONAL_FIRST_SPEECH_OFFSET_SEC = 7;

/** POST /postFractionalPlan / expandFractionalCues — intro block length bounds (see docs/intro-fractional-composer.md). */
export const INT_FRAC_PLAN_MIN_DURATION_SEC = 20;
/** 10m+ practice targets this cap (60s intro). */
export const INT_FRAC_PLAN_MAX_DURATION_SEC = 60;
