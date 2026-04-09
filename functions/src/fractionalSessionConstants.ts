/**
 * @see ../../docs/fractional-module-intro-rule.md — single product reference for all fractional modules.
 */
export const FRACTIONAL_INTRO_MIN_DURATION_SEC = 300;

/** POST /postFractionalPlan / expandFractionalCues — intro block length bounds (see docs/intro-fractional-composer.md). */
export const INT_FRAC_PLAN_MIN_DURATION_SEC = 17;
/** Upper cap; actual window also scales from session length (shortest ~1m session, up to this for 10m+). */
export const INT_FRAC_PLAN_MAX_DURATION_SEC = 90;
