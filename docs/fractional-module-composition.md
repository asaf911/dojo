# Fractional Module Composition

How fractional meditation modules are composed at runtime from atomic audio clips.
This document serves as a reference for building new fractional modules.

**Body scan (BS_FRAC)** uses a separate tier-based composer — see [`body-scan-tier-composer.md`](./body-scan-tier-composer.md).

**Intro (`INT_FRAC`)** uses a dedicated layered composer (7s lead-in before first speech) — see [`intro-fractional-composer.md`](./intro-fractional-composer.md).

**Morning Visualization (`MV_KM_FRAC` / `MV_GR_FRAC`)** uses a dedicated composer — [`functions/src/morningVisualizationPlan.ts`](../functions/src/morningVisualizationPlan.ts) — with one shared catalog [`functions/catalogs/morning_visualization_fractional.json`](../functions/catalogs/morning_visualization_fractional.json). Clips use the `MVK_*` prefix for Key Moments and `MVG_*` for Gratitude (duplicate shared rows so Timer collapse stays theme-correct). The opening **shared orientation** (MV_INT_100 / 110 / 120) uses `role: instruction` with orders 100–120 — not `intro` — so it still plays when MV is **not** the first module on the timeline (fractional framing-intro rules only suppress `role: intro`). First two lines are **p0** (sequential); the third (room detail) is **p2** in the catalog so trimming drops it before body **p1** instructions (product: reinforcement when time allows). Then: **body instructions → optional reminders (≥ 2 min) → ordered multi-clip outro** at session end. Reminder count is **capped** by MV window length (**none** for blocks under 3 minutes, then at most **1** until 5 minutes, **2** until 7 minutes, then all eligible), gaps between reminders must be at least **~18s**, and **“If attention drifts, return to the scene”** (`MVK_C008` / `MVG_C008`) is omitted unless the MV block is **≥ 6 minutes**. Tests: [`functions/src/morningVisualizationPlan.test.ts`](../functions/src/morningVisualizationPlan.test.ts).

Optional catalog fields for MV inventory / QA: `contentTrack` (e.g. `Key Moments`, `Morning Gratitude`) and `reminderPurpose` (e.g. `Reinforce flow`). Example — shared asset `MV_REM_420_MOVE_WITH_EASE_ASAF.mp3`: **reminder**, on-screen/script line **Continue moving through your day**; `MVK_C009` → `contentTrack: Key Moments`, `reminderPurpose: Reinforce flow`; `MVG_C009` → same audio in the gratitude variant with `contentTrack: Morning Gratitude`.

**Evening Visualization (`EV_KM_FRAC` / `EV_GR_FRAC`)** uses a **deterministic** composer — [`functions/src/eveningVisualizationPlan.ts`](../functions/src/eveningVisualizationPlan.ts) — with catalog [`functions/catalogs/evening_visualization_fractional.json`](../functions/catalogs/evening_visualization_fractional.json). Clips use `EVK_*` (retrospection) and `EVG_*` (gratitude); shared orientation and shared reminders are duplicated per prefix like MV. Under time pressure the composer **drops optional clips** by `priority` (`p2` / `p1` before `p0`) rather than randomizing reminders. Tests: [`functions/src/eveningVisualizationPlan.test.ts`](../functions/src/eveningVisualizationPlan.test.ts).

## Module intro (1–4 min vs first on timeline)

Every fractional module shares one **framing intro** policy: **no module intro for under 5 minutes** unless the block is **at meditation start (t=0)** **and** **first fractional row** **and** **no regular cue precedes it** (or standalone `postFractionalPlan` with `atTimelineStart`). Authoritative spec: [**`fractional-module-intro-rule.md`**](./fractional-module-intro-rule.md).

## Overview

A fractional module is defined by a **catalog JSON** containing a flat list of audio clips.
At request time the server selects a subset of clips based on the session duration,
assigns each clip a second-precision timestamp, and returns them as regular cues.
The client doesn't need to know the composition happened — it receives a normal `MeditationPackage`.

Composition follows a **two-phase** approach:

1. **Select** — decide which clips to include based on priority and available time.
2. **Place** — assign timestamps using a growing-gap progression.

---

## Catalog Structure

Each fractional module has a JSON file under `functions/catalogs/`.

```jsonc
{
  "version": "1.0",
  "moduleId": "NF_FRAC",
  "title": "Nostril Focus",
  "clips": [
    {
      "clipId": "NF_C001",
      "role": "intro",          // "intro" | "instruction" | "reminder"
      "order": 1,               // determines timeline position
      "text": "We will now begin a focus exercise.",
      "voices": {
        "Asaf": "modules/nostril_focus_fractional/asaf/NF_C001_ASAF.mp3"
      }
      // intro clips have no priority field
    },
    {
      "clipId": "NF_C003",
      "role": "instruction",
      "order": 3,
      "priority": "p0",        // "p0" | "p1" | "p2"
      "text": "Direct your attention to the sensation of the breath in your nose.",
      "voices": { ... }
    },
    {
      "clipId": "NF_C007",
      "role": "reminder",
      "order": 7,
      "text": "Keep your attention on the breath in your nose.",
      "voices": { ... }
      // reminder clips have no priority field
    }
  ]
}
```

### Clip roles

| Role          | Purpose                                    | Priority field? |
|---------------|--------------------------------------------|-----------------|
| `intro`       | Opening line, sets context                 | No — governed by duration threshold |
| `instruction` | Core teaching content                      | Yes (`p0` / `p1` / `p2`)           |
| `reminder`    | Gentle nudges to refocus; interchangeable  | No — randomly selected, no repeats  |

### Priority levels (instructions only)

| Priority | Meaning | Selection rule |
|----------|---------|----------------|
| `p0`     | Essential — the single most critical instruction | Always included, regardless of duration |
| `p1`     | Important — core supporting instructions | Included when time budget allows; shuffled for variety |
| `p2`     | Supplementary — enriching but optional | Fills remaining slots after P0 and P1; shuffled |

---

## Phase 1: Clip Selection

### Intro threshold (module framing only)

Same rule as all fractional modules: see [**`fractional-module-intro-rule.md`**](./fractional-module-intro-rule.md). NF/IM implementation: `selectClips` in `fractionalComposer.ts` uses `FRACTIONAL_INTRO_MIN_DURATION_SEC` and `atTimelineStart` on `composeFractionalPlan`.

### Instruction selection

1. All **P0** clips are unconditionally included.
2. **P1** clips are shuffled and added as candidates.
3. **P2** clips are shuffled and added as candidates.
4. Candidates are sorted by catalog `order`.
5. If the **unified schedule** would exceed the duration, the lowest-priority clips
   are removed from the tail: P2 first, then P1. P0 clips are never removed.
   Feasibility uses the same placement rules as the final plan (`nfImSelectionFits` → `scheduleNfImPlan`).

### Reminder count

| Duration     | Reminder rule |
|--------------|---------------|
| < 2 min      | 0 reminders   |
| >= 2 min     | Minimum 1; as many as the time budget allows |
| Any duration | Capped at the number of unique reminder clips (no repeats) |

The budget check iteratively tries adding 1, 2, 3… reminders and stops when the
next set would no longer fit. Reminders are picked randomly
from the pool with no repeats, providing a varied experience across sessions.

---

## Phase 2: Timeline placement (NF_FRAC / IM_FRAC)

Implementation: [`functions/src/fractionalTimeline.ts`](../functions/src/fractionalTimeline.ts) (`scheduleNfImPlan`).  
Spec tests: [`functions/src/fractionalNfImTimeline.test.ts`](../functions/src/fractionalNfImTimeline.test.ts).

Selected clips are ordered by catalog `order`, then scheduled on a **float** timeline; cue `atSec` values are **rounded to whole seconds** for triggers. Clip lengths use optional per-clip **`durationSec`** in the catalog (populate via `npm run scan:fractional-nf-im-durations` in `functions/`, which wraps the shared Firebase MP3 scanner); if missing, a **5 s** fallback is used.

### Instruction segment (intro + instructions)

- Silence after each clip is based on an exponential **instruction gap** (same family as the previous composer: base scales slightly with session length, capped at 30 s), except optional **pair overrides**: `FRACTIONAL_INSTRUCTION_PAIR_GAPS` in `fractionalTimeline.ts` (e.g. IM `IM_C002` → `IM_C003` = 5 s).
- The internal cursor advances by **float** end times so gap proportions stay stable; rounding applies only when emitting `atSec`.

### Reminder segment

- After the last instruction, remaining time (minus an explicit **tail** slice and, for IM, space before **outro**) is split into **pre-reminder gaps**.
- Gaps form a **linear ramp** from a floor (at least the instruction gap floor, 15 s minimum) toward a last gap (capped), then **scaled** so the sum matches the gap budget exactly (monotonic non-decreasing in float space).

### Outro (IM_FRAC only when duration allows)

- Placed near `durationSec - outroDuration - padding`, with at least **8 s** after the last reminder ends.

### Tail

- A fraction of the post-instruction **span** (default ~15%, clamped) is reserved as tail before the hard end (or before outro), so the block does not end immediately after the last reminder.

---

## Example Timelines (illustrative — exact times depend on `durationSec` and voice)

### 1 minute (60 s)

| Time  | Clip   | Role        | Priority |
|-------|--------|-------------|----------|
| 0:00  | C002   | instruction | P1       |
| 0:10  | C003   | instruction | P0       |
| 0:23  | C004   | instruction | P1       |
| 0:39  | C005   | instruction | P2       |

No intro, no reminders. ~20 s trailing silence.

### 3 minutes (180 s)

| Time  | Clip   | Role        |
|-------|--------|-------------|
| 0:00  | C002   | instruction |
| 0:10  | C003   | instruction |
| 0:21  | C004   | instruction |
| 0:32  | C005   | instruction |
| 0:44  | C006   | instruction |
| 0:58  | C007   | reminder    |
| 1:12  | C008   | reminder    |
| 1:28  | C009   | reminder    |
| 1:45  | C010   | reminder    |
| 2:04  | C012   | reminder    |
| 2:25  | C013   | reminder    |

5 instructions + 6 reminders. Gaps grow from 10 s to ~21 s. ~35 s trailing silence.

### 5 minutes (300 s)

| Time  | Clip   | Role        |
|-------|--------|-------------|
| 0:00  | C001   | intro       |
| 0:10  | C002   | instruction |
| 0:21  | C003   | instruction |
| 0:33  | C004   | instruction |
| 0:46  | C005   | instruction |
| 1:01  | C006   | instruction |
| 1:18  | C007   | reminder    |
| 1:36  | C008   | reminder    |
| 1:58  | C009   | reminder    |
| 2:22  | C010   | reminder    |
| 2:50  | C011   | reminder    |
| 3:22  | C012   | reminder    |
| 3:59  | C013   | reminder    |

Intro included (>= 4 min). All 13 clips used. Gaps grow from 10 s to ~37 s.

### 10 minutes (600 s)

| Time  | Clip   | Role        |
|-------|--------|-------------|
| 0:00  | C001   | intro       |
| 0:13  | C002   | instruction |
| 0:28  | C003   | instruction |
| 0:45  | C004   | instruction |
| 1:04  | C005   | instruction |
| 1:26  | C006   | instruction |
| 1:52  | C007   | reminder    |
| 2:23  | C008   | reminder    |
| 2:59  | C009   | reminder    |
| 3:42  | C010   | reminder    |
| 4:33  | C011   | reminder    |
| 5:33  | C012   | reminder    |
| 6:46  | C013   | reminder    |

All 13 clips. Gaps grow from 13 s to ~73 s. ~3+ min trailing silence.

---

## Applying This Pattern to New Modules

### What's generic (reuse as-is)

- The two-phase select-then-place architecture
- `scheduleNfImPlan` for NF/IM-style catalogs (instruction ramp + reminder ramp + tail)
- Priority system (P0 / P1 / P2) for instructions
- Random reminder selection with no repeats
- Shared framing intro rule ([`fractional-module-intro-rule.md`](./fractional-module-intro-rule.md))
- Reminder threshold (>= 2 min)
- Selection trim loop using the same scheduler as placement

### What's module-specific (customize per module)

- **Clip catalog**: different clips, roles, texts, voices
- **Priority assignments**: which clips are P0/P1/P2 depends on the teaching content
- **`durationSec` per clip** (recommended): run the scanner so schedules match real audio
- **Pair gaps**: extend `FRACTIONAL_INSTRUCTION_PAIR_GAPS` for fixed pauses between named instruction clips

### Adding a new module

1. Create `functions/catalogs/<module_slug>.json` following the catalog schema above.
2. Add an entry to `FRACTIONAL_MODULE_MAP` in `fractionalComposer.ts`:
   ```typescript
   const FRACTIONAL_MODULE_MAP: Record<string, string> = {
     NF_FRAC: "nostril_focus_fractional",
     XX_FRAC: "your_new_module",
   };
   ```
3. Add a catalog entry in `functions/catalogs/<parent_catalog>.json` with `"fractional": true`.
4. If the module needs different placement logic than NF/IM, add a dedicated composer (as for `PB_FRAC` / `BS_FRAC`) rather than overloading `fractionalTimeline.ts`.
