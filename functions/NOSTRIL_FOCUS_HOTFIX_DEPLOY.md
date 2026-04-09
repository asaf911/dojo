# Nostril Focus monolithic hotfix — deploy checklist

Deploy **Firebase Cloud Functions** only (no iOS release required for server-side catalog + cue ids).

## Pre-deploy

1. From `functions/`: `npm test` (must pass).
2. Confirm GCS assets exist: `gs://imagine-c6162.appspot.com/modules/nostril_focus/asaf/nostril-focus-{1..10}min.mp3`.

## Deploy

```bash
cd functions && npm run build && npm run deploy
```

Or: `firebase deploy --only functions` from the repo root with the correct Firebase project selected (`imagine-c6162` / production alias per your workflow).

## Post-deploy smoke

1. **GET catalogs** — Response JSON should list cue ids `NF1` … `NF10` under `cues` with `gs://imagine-c6162.appspot.com/modules/nostril_focus/...` URLs. `NF_FRAC` should **not** appear in `cues`.
2. **POST postMeditations (manual)** — Body with legacy `NF_FRAC` in `cues` should still resolve (rewritten to `NFk`) after deploy.
3. **AI meditation** — Request with nostril-related prompt should return expanded cues without atomic `NF_C###` ids for the focus block (single `NFk` cue per focus segment).

## Rollback

Redeploy the previous Functions build or revert the commit and redeploy.
