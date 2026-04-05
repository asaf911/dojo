# Fractional Module Composition

How fractional meditation modules are composed at runtime from atomic audio clips.
This document serves as a reference for building new fractional modules.

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

### Intro threshold

The intro clip is included only when `durationSec >= 240` (4 minutes).
Short sessions (1–3 min) skip the intro and jump straight into instructions.

### Instruction selection

1. All **P0** clips are unconditionally included.
2. **P1** clips are shuffled and added as candidates.
3. **P2** clips are shuffled and added as candidates.
4. Candidates are sorted by catalog `order`.
5. If the estimated timeline exceeds the duration, the lowest-priority clips
   are removed from the tail: P2 first, then P1. P0 clips are never removed.

### Reminder count

| Duration     | Reminder rule |
|--------------|---------------|
| < 2 min      | 0 reminders   |
| >= 2 min     | Minimum 1; as many as the time budget allows |
| Any duration | Capped at the number of unique reminder clips (no repeats) |

The budget check iteratively tries adding 1, 2, 3… reminders and stops when the
estimated total timeline would exceed the duration. Reminders are picked randomly
from the pool with no repeats, providing a varied experience across sessions.

---

## Phase 2: Timeline Placement

Selected clips are placed in `order` sequence with **growing gaps**.

### Gap progression

Gaps between clips grow linearly from `initialGap` to `targetGap`:

```
gap[step] = initialGap + (targetGap - initialGap) * step / (totalGaps - 1)
```

This ensures the absolute increment between consecutive gaps stays constant,
producing a balanced, predictable progression at any duration. Each gap is
capped at `capGap` to prevent absurdly long silences.

### Gap tiers by duration

| Duration       | Initial gap | Target gap | Cap   |
|----------------|-------------|------------|-------|
| 1–3 min        | 5 s         | 18 s       | 20 s  |
| 4–6 min        | 5 s         | 38 s       | 45 s  |
| 7–8 min        | 7 s         | 55 s       | 60 s  |
| 9–10 min       | 8 s         | 82 s       | 90 s  |
| 10+ min        | 10 s        | 105 s      | 120 s |

### Trailing buffer

After the last clip, a trailing silence of **1.1× the last gap used** is
factored into the timeline estimate. This ensures the module doesn't end
abruptly — there's always breathing room before the next module or session end.

---

## Example Timelines

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
- Gap tier table and growth factor computation
- Priority system (P0 / P1 / P2) for instructions
- Random reminder selection with no repeats
- Intro threshold (>= 4 min)
- Reminder threshold (>= 2 min)
- Trailing buffer (1.1× last gap)
- Timeline estimation and trim loop

### What's module-specific (customize per module)

- **Clip catalog**: different clips, roles, texts, voices
- **Priority assignments**: which clips are P0/P1/P2 depends on the teaching content
- **Intro threshold**: some modules may always need an intro, or never
- **Reminder threshold**: could be adjusted per module
- **Gap tiers**: meditative modules may want wider gaps; active exercises may want tighter ones
- **Clip duration estimate**: currently a flat 5 s; modules with longer clips should adjust

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
4. If the module needs custom thresholds or gap tiers, extend `composeFractionalPlan`
   to accept module-level overrides (or create a per-module config alongside the catalog).
