# Intro fractional module (`INT_FRAC`)

Layered opening segment for meditation: **Greeting**, **Arrival**, and **Orientation** clips from [`functions/catalogs/intro_fractional.json`](../functions/catalogs/intro_fractional.json).

## Behavior

- **First speech** starts **7 seconds** after the module window begins (background music at second 0 of the block).
- **End pause:** **5 seconds** of silence after the last clip ends, before the next cue/module (fits within the allocated intro window).
- **Intro window length (dev):** Derived from **practice duration** (the timer minutes the user chose) — shortest target (~18s) for a **1-minute** practice, up to **90s** for **10+ minute** practice. Implemented by [`introWindowSecFromSessionDurationSec`](../functions/src/introFractionalPlan.ts). **Timeline model:** intro is a **prefix** — total playback = practice length + intro length. Numeric minute triggers in `postMeditations` are **practice-relative** (minute `1` = first minute of practice); [`applyPracticeRelativeIntroPrefix`](../functions/src/fractionalComposer.ts) maps them to absolute `s{sec}` on the session clock (`introPrefix + minute×60`). Manual per-cue duration is not used for `INT_FRAC`.
- **Selection:** **≤1 minute** sessions use **one clip only** (orientation preferred, then arrival, then greeting). Longer sessions **greedily** add greeting → arrivals in catalog order (skipping lines that no longer fit) → orientation, within the window. At most one greeting (mutually exclusive families: good morning / good evening / welcome / welcome back); arrivals remain **compatible** (never both posture variants `INT_ARR_120` and `INT_ARR_122`; never both `INT_ARR_124` and `INT_ARR_126`); at most one orientation (`INT_ORI_140`).
- **Composer:** [`functions/src/introFractionalPlan.ts`](../functions/src/introFractionalPlan.ts) (`composeIntroFractionalPlan`).

## API

`POST /postFractionalPlan` with `moduleId: "INT_FRAC"`:

- **`durationSec`:** Total **session** length in seconds — same as other modules: **`60`–`1200`**. The server computes the intro block length with `introWindowSecFromSessionDurationSec(durationSec)` and composes that many seconds of intro audio.

Other fractional modules use **`durationSec`** as the **module** window (unchanged).

Bounds on the composed intro block: [`INT_FRAC_PLAN_MIN_DURATION_SEC` / `INT_FRAC_PLAN_MAX_DURATION_SEC`](../functions/src/fractionalSessionConstants.ts) (currently 17–90s target cap).

## Inline expansion

Session builders resolve `INT_FRAC` from catalogs (see [`functions/catalogs/introduction.json`](../functions/catalogs/introduction.json)); [`expandFractionalCues`](../functions/src/fractionalComposer.ts) applies the intro prefix, then expands using **practice duration** for intro composition and **full playback duration** for module windows (dev project only; see [`deploymentMode.ts`](../functions/src/deploymentMode.ts)). `POST /meditations` responses include optional **`playbackDurationSec`** (practice + intro seconds).

## MP3 durations

Populate `durationSec` on each clip (Firebase public URLs) via:

```bash
cd functions && npm run scan:intro-frac-durations
```

## Related

- NF/IM-style composition: [`fractional-module-composition.md`](./fractional-module-composition.md)
- “Framing intro” rule for other fractional modules: [`fractional-module-intro-rule.md`](./fractional-module-intro-rule.md) — **`INT_FRAC` is different** (it is the intro itself, not an NF/IM `role: intro` line).
