# Perfect Breath fractional composer (`PB_FRAC`)

Server: [`functions/src/perfectBreathPlan.ts`](../functions/src/perfectBreathPlan.ts). Catalog: [`functions/catalogs/perfect_breath_fractional.json`](../functions/catalogs/perfect_breath_fractional.json).

## API

- `POST /postFractionalPlan` with `moduleId: "PB_FRAC"`, `durationSec` (60–1200), `voiceId`.
- Inline expansion: `expandFractionalCues` maps `PB_FRAC` the same way as other fractional modules; breath phase minutes map to `durationMinutes` on the cue (see [`cueBuilder.ts`](../functions/src/cueBuilder.ts)).

## Storage filenames vs `clipId`

Stable **`clipId`** values in the catalog (e.g. `PBV_BREATH_100`) are what the composer and plan JSON use. **`voices.Asaf`** must be the **real object name** under `modules/perfect_breath_fractional/asaf/`, for example:

| clipId | File (Asaf) |
|--------|-------------|
| `PBV_BREATH_100` | `PBV_BREATH_100_INHALE_EXPAND_FULL_ASAF.mp3` |
| `PBV_BREATH_110` | `PBV_BREATH_110_EXHALE_RELAX_FULL_ASAF.mp3` |
| `PBV_BREATH_120` | `PBV_BREATH_120_INHALE_EXPAND_MEDIUM_ASAF.mp3` |
| `PBV_BREATH_130` | `PBV_BREATH_130_EXHALE_RELAX_MEDIUM_ASAF.mp3` |
| `PBV_BREATH_140` | `PBV_BREATH_140_INHALE_EXPAND_SHORT_ASAF.mp3` |
| `PBV_BREATH_150` | `PBV_BREATH_150_EXHALE_RELAX_SHORT_ASAF.mp3` |
| `PBV_BREATH_160` | `PBV_BREATH_160_INHALE_EXPAND_MINIMAL_ASAF.mp3` |
| `PBV_BREATH_170` | `PBV_BREATH_170_EXHALE_RELAX_MINIMAL_ASAF.mp3` |
| `PBV_BREATH_320_FINAL_EXHALE_ASAF` | `PBV_BREATH_320_FINAL_EXHALE_END_ASAF.mp3` |

Other clips (`200`, `230`, `240`–`248`, `250`, `280`, `322`, `OPEN`, `PBS_*`) already matched full names in Storage.

## Parallel SFX in JSON

Plan items may include optional `parallel` (same session second as the primary clip):

```json
{
  "atSec": 12,
  "clipId": "PBV_BREATH_100",
  "role": "instruction",
  "text": "…",
  "url": "gs://…/PBV_BREATH_100_INHALE_EXPAND_FULL_ASAF.mp3",
  "parallel": {
    "clipId": "PBS_IN",
    "url": "gs://…/PBS_IN.mp3",
    "text": "Breath SFX inhale"
  }
}
```

iOS maps this to `Cue.parallelSfx` and mixes on a second `AVAudioPlayerNode`. `postMeditations` / AI responses use `parallelSfx: { id, name, url }` on each expanded cue.

## Cue timing (no overlap)

The app triggers fractional cues on **whole-second** `elapsed` times. The composer schedules each voice clip at `ceil(cursor)` seconds (after an optional epsilon), then advances the internal cursor so the next cue does not start too early.

### Preparation (`PBV_BREATH_100`–`170`)

**Breath SFX (`PBS_IN` / `PBS_OUT`) sets the cadence**, not narration length. Each prep inhale item includes parallel `PBS_IN`; each prep exhale includes `PBS_OUT`. Both start on the same `atSec`.

| Segment | Duration |
|---------|----------|
| Inhale SFX window | 5 s |
| Gap (silence) | 2 s |
| Exhale SFX window | 5 s |
| Gap (silence) | 1 s |

Then the next prep inhale (or `200` after the last exhale). One inhale+exhale pair = **13 s** of timeline. Narration clips can be shorter than 5 s; if they run long, the next scheduled cue still starts on time (player moves on). **`PBS_IN` / `PBS_OUT` files should be mastered close to 5 s** so the sound matches the grid.

### Rest of the plan

After preparation, the cursor advances by **`atSec + durationSec`** from the catalog for each voice cue (same as before). Re-scan `durationSec` after any asset change.

## Constants

| Constant | Seconds | Notes |
|----------|---------|--------|
| After intro (`PBV_OPEN_000`) | 2 | Silence before first prep inhale |
| Before `PBV_BREATH_230` | 2 | Early in top hold |
| After `230` | 2 | Before release line |
| Recovery top hold after `280` | 5 | No extra voice |
| Between cycles (after `322`) | 10 | Next cycle starts at `100` |

## Selection

- **Prep pairs**: 2 (short sessions), 3 (≥300s), 4 (≥540s).
- **Release / bottom hold**: one of `240`–`248` tiers (10–30s hold), chosen from total `durationSec`; composer may step down if the plan would exceed `durationSec`.
- **Cycles**: As many full cycles as fit; the **last** cycle always ends with `PBV_BREATH_320_FINAL_EXHALE_ASAF` (never `322`).
- **Mid-bottom-hold**: `PBV_HOLD_250_THOUGHTS_ESCAPE_ASAF` at ~50% of the bottom-hold window; timeline advances by `max(hold, midpoint + clip250Duration)` so overlap is handled.

## Durations

Run from `functions/`:

```bash
node scripts/scanBodyScanDurations.mjs perfect_breath_fractional.json
```

Uses `music-metadata` with `{ duration: true }` on the Firebase download stream. Re-run after any Storage rename or new upload.

## Deprecations

- Monolithic `PB1`–`PB5` are in `DEPRECATED_CUE_IDS` and removed from `getCatalogs`.
- Catalog entry for the timer picker: [`functions/catalogs/perfect_breath.json`](../functions/catalogs/perfect_breath.json) → single `PB_FRAC` with `"fractional": true`.
