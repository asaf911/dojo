/**
 * Time-of-day soundscape preferences for AI meditation (Firebase `generateAIMeditation`).
 *
 * IDs must exist in `functions/catalogs/background_music.json` and in live GET /catalogs.
 * When adding a new soundscape: add the row to the catalog, deploy, then extend the
 * relevant `preferredIds` / `avoidIds` here — this file is the product intent map.
 *
 * Human names → ids: Oasis OA, Bird BD, Peaceful Transient PT, Ocean OC,
 * Samagaun ES, Lush Infinity LI, Dharapani DH, Spa SP.
 */

/** Timely blueprints wired in `meditationBlueprints.ts` (sleep / scenarios use separate hints). */
export type TimelySoundscapeBlueprintId =
  | "timely.morning"
  | "timely.noon"
  | "timely.evening"
  | "timely.night";

export interface SoundscapeWindowHints {
  readonly preferredIds: readonly string[];
  readonly avoidIds?: readonly string[];
}

export const SOUNDSCAPE_TIME_PLAN: Record<
  TimelySoundscapeBlueprintId,
  SoundscapeWindowHints
> = {
  "timely.morning": {
    preferredIds: ["OA", "BD", "PT"],
  },
  "timely.noon": {
    preferredIds: ["DH", "SP", "LI"],
  },
  "timely.evening": {
    preferredIds: ["OC", "ES", "LI"],
    avoidIds: ["OA"],
  },
  "timely.night": {
    preferredIds: ["OC", "ES", "LI"],
    avoidIds: ["OA"],
  },
};
