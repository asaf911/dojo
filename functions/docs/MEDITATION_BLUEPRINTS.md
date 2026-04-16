# Meditation blueprints (server)

Product meditation **templates** live in `functions/src/meditationBlueprints.ts`. Each row (`MeditationBlueprint`) defines:

- **`id`** — stable string in `BLUEPRINT_IDS` (e.g. `timely.morning`, `scenario.pre_important_event`).
- **`phaseIntent`** — documentation of the intended arc (intro → breath → relax → terminal).
- **`terminalMode`** — how the fractional cue row is chosen (`MV_*`, `EV_*`, `IM_FOCUS`, `NIGHT_IM_THEN_EV`, `SLEEP_AMBIENT`, …).
- **`audioHints`** — `backgroundSound` (`preferCategory`, `preferredIds`, `avoidIds`) and optional `binauralBeat.preferredIds`. Used by `pickBackgroundSoundForBlueprint` / `pickBinauralBeatForBlueprint` in `generateAIMeditation` so catalog picks align with the same template that drives cues.

## Resolution order

`resolveBlueprintFromContext` (called from `generateAIMeditation`):

1. If the client sends a valid **`clientBlueprintId`** / HTTP **`blueprintId`**, that blueprint wins.
2. Otherwise themes + `SessionPreferences` map to a timely template (e.g. `night` → `timely.night`, `sleep` / `isSleep` → `timely.sleep`).

iOS sends optional **`AIServerRequestContext.blueprintId`** (see `SenseiMeditationBlueprintID.swift`) together with **`meditationThemes`** for Sensei timely generation.

## Adding a new scenario (e.g. pre-event)

1. Add a new id to **`BLUEPRINT_IDS`** and a **`BLUEPRINTS`** row in `meditationBlueprints.ts` (`terminalMode`, `audioHints`, etc.).
2. If the client should force that template, send **`blueprintId`** on `/ai/request` or POST `/meditations` (`type: "ai"`) and optionally matching **`meditationThemes`** for prompt merge.
3. Add the same id string to **`SenseiMeditationBlueprintID`** on iOS wherever that path builds `AIServerRequestContext` or the POST `/meditations` AI JSON body (`MeditationsService`).
4. Extend **`MEDITATION_THEME_IDS`** / theme parsing in `meditationThemes.ts` only if the scenario is also expressed as a **theme tag** merged from the prompt.

## Optional audio overrides

`audioHints.backgroundSound` participates in weights before `recentBackgroundSounds` down-weighting. User-facing per-template sound preferences would be a separate merge layer on top of this registry (not implemented here).
