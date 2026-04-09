# Intro fractional module (`INT_FRAC`)

Layered opening segment for meditation: **Greeting**, **Arrival**, and **Orientation** clips from [`functions/catalogs/intro_fractional.json`](../functions/catalogs/intro_fractional.json).

## Behavior

- **First speech** starts **7 seconds** after the module window begins (background music at second 0 of the block).
- **End pause:** **5 seconds** of silence after the last clip ends, before the next cue/module (fits within the allocated `durationSec`).
- **Selection:** At most one greeting (mutually exclusive families: good morning / good evening / welcome / welcome back), up to two **compatible** arrival clips (never both posture variants `INT_ARR_120` and `INT_ARR_122`; never both `INT_ARR_124` and `INT_ARR_126`), at most one orientation clip (`INT_ORI_140`).
- **Composer:** [`functions/src/introFractionalPlan.ts`](../functions/src/introFractionalPlan.ts) (`composeIntroFractionalPlan`).

## API

`POST /postFractionalPlan` with `moduleId: "INT_FRAC"`:

- **`durationSec`:** **`17`–`120`** (see [`INT_FRAC_PLAN_MIN_DURATION_SEC` / `INT_FRAC_PLAN_MAX_DURATION_SEC`](../functions/src/fractionalSessionConstants.ts)). Shorter than 17s may not fit even a single clip with the 7s lead-in, end pause, and fallback clip durations.

Other fractional modules remain **`60`–`1200`** seconds.

## Inline expansion

Session builders resolve `INT_FRAC` from catalogs (see [`functions/catalogs/introduction.json`](../functions/catalogs/introduction.json)); [`expandFractionalCues`](../functions/src/fractionalComposer.ts) expands it into second-precision cues like other `*_FRAC` modules.

## MP3 durations

Populate `durationSec` on each clip (Firebase public URLs) via:

```bash
cd functions && npm run scan:intro-frac-durations
```

## Related

- NF/IM-style composition: [`fractional-module-composition.md`](./fractional-module-composition.md)
- “Framing intro” rule for other fractional modules: [`fractional-module-intro-rule.md`](./fractional-module-intro-rule.md) — **`INT_FRAC` is different** (it is the intro itself, not an NF/IM `role: intro` line).
