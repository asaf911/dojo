# Fractional module intro (product rule)

**Scope:** Every **fractional** meditation module in this repo — `NF_FRAC`, `IM_FRAC`, `PB_FRAC`, `BS_FRAC` / `BS_FRAC_UP` / `BS_FRAC_DOWN`.

**Exception — `INT_FRAC`:** The layered **Intro** module is **not** an NF/IM-style “framing intro” clip. It **is** the composed opening (greeting / arrival / orientation). See [`intro-fractional-composer.md`](./intro-fractional-composer.md). Do not confuse with **`INT_GEN_*`** monolithic intro cues.

**Not in scope:** Session-level cues such as **`INT_GEN_*`** (general meditation opening). Those are composed outside fractional composers (`postMeditations`, `postAIRequest`, etc.).

---

## Rule (plain language)

- **Under 5 minutes** (`durationSec < 300`): **no** module framing intro — **unless** this fractional block is the **actual start of the meditation** (its window begins at session second **0**), it is the **first fractional row** in the cue list, and **no non-fractional cue** appears **above** it (so a general intro like **`INT_GEN_*`** or any regular module first → the following fractional module does **not** get a framing intro). Standalone: **`POST /postFractionalPlan`** with **`atTimelineStart: true`** still opts in.
- **5 minutes or longer** (`durationSec >= 300`): framing intro is **allowed** (still subject to body-scan `introShort` / `introLong`, and composer fit logic).

**Wording note:** “1–4 minutes” in product copy maps to **under 5 minutes** in code; the boundary is **`FRACTIONAL_INTRO_MIN_DURATION_SEC` (300 seconds)**, not 240.

**Perfect Breath (`PB_FRAC`) extra constraint:** The `PBV_OPEN_000` line is **never** scheduled for the **1-minute** fractional window (`durationSec <= 60`), so the tight breath grid still fits. For 61–299 seconds, the same “skip unless at timeline start” rule applies as for other modules.

---

## What counts as “module intro”

| Module(s) | Framing intro |
|-----------|----------------|
| NF / IM | Catalog clips with `role: "intro"` (e.g. “we will now begin a focus exercise”) |
| Body scan | Short and/or long `intro` clips (“we will now begin a body scan” family), per API flags |
| Perfect Breath | `PBV_OPEN_000_INTRO` (`PBV_OPEN_000` in catalog) |
| Intro (`INT_FRAC`) | *N/A* — entire module is layered intro audio (not a separate framing line) |

---

## How “first on timeline” is represented

| Path | Mechanism |
|------|-----------|
| **`POST /postFractionalPlan`** | Request field **`atTimelineStart: true`** when this module is played as the first block (e.g. standalone Fractional Modules dev screen, or a client that knows the block starts at 0). If omitted or `false`, short sessions skip framing intros. |
| **Inline expansion** (`expandFractionalCues` in `postMeditations` / `postAIRequest`) | **`atTimelineStart`** is **`true` only when** (1) this cue’s resolved window starts at **second 0**, (2) it is the **first fractional row** in the list, and (3) **every cue above it** is also fractional (there are **no** regular rows before it). So **regular module → fractional** at `start` still **suppresses** the fractional framing intro for short windows. A **second** fractional row with a bogus `trigger: "start"` is also excluded (not the first fractional index). |

Constant: **`FRACTIONAL_INTRO_MIN_DURATION_SEC`** (`300`) in [`functions/src/fractionalSessionConstants.ts`](../functions/src/fractionalSessionConstants.ts).

---

## Implementation map (for agents)

| Module | File | Notes |
|--------|------|--------|
| NF / IM | [`functions/src/fractionalComposer.ts`](../functions/src/fractionalComposer.ts) | `composeFractionalPlan(..., atTimelineStart)` → `selectClips` |
| Body scan | [`functions/src/bodyScanTierPlan.ts`](../functions/src/bodyScanTierPlan.ts) | `BodyScanTierPlanParams.atTimelineStart` → `chooseBodyScanPlan` |
| Perfect Breath | [`functions/src/perfectBreathPlan.ts`](../functions/src/perfectBreathPlan.ts) | `includePerfectBreathOpenVoice` + `composePerfectBreathPlan(..., atTimelineStart)` |
| Intro | [`functions/src/introFractionalPlan.ts`](../functions/src/introFractionalPlan.ts) | `composeIntroFractionalPlan` — **ignores** NF/IM framing intro rule |
| HTTP entry | [`functions/src/index.ts`](../functions/src/index.ts) | `postFractionalPlan` parses `atTimelineStart`, passes into composers (not used by `INT_FRAC`) |
| iOS (dev / standalone) | [`ios/imagine/Features/FractionalModules/FractionalModules+Service.swift`](../ios/imagine/Features/FractionalModules/FractionalModules+Service.swift) | Sends `atTimelineStart: true` from the Fractional Modules flow |

---

## Related docs

- Layered Intro (`INT_FRAC`): [`intro-fractional-composer.md`](./intro-fractional-composer.md)
- Generic NF/IM composition: [`fractional-module-composition.md`](./fractional-module-composition.md)
- Body scan tier composer: [`body-scan-tier-composer.md`](./body-scan-tier-composer.md)
- Perfect Breath timeline: [`perfect-breath-fractional-composer.md`](./perfect-breath-fractional-composer.md)
