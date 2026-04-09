/**
 * Production (`imagine-c6162`): fractional is NOT supported — monolithic / legacy cues only.
 * Dev (`imaginedev-e5fd3`): fractional supported — use fractional catalogs and *_FRAC ids where defined.
 * GCLOUD_PROJECT is set automatically in deployed Cloud Functions.
 */

const DEV_FRACTIONAL_PROJECT_ID = "imaginedev-e5fd3";

/**
 * `false` → production: load `*_legacy.json`, monolithic cue ids, expandFractionalCues no-op, postFractionalPlan 403.
 * `true` → dev: load fractional JSON, cueBuilder emits *_FRAC, full expansion + postFractionalPlan.
 */
export function useFractionalModulesInCatalogsAndAI(): boolean {
  const project =
    process.env.GCLOUD_PROJECT ?? process.env.GCP_PROJECT ?? "";
  return project === DEV_FRACTIONAL_PROJECT_ID;
}
