# Production vs development servers (catalogs & fractional modules)

Behavior is chosen at **runtime** from `process.env.GCLOUD_PROJECT` (set automatically on deployed Cloud Functions). No client flag.

## Production — `imagine-c6162` (App Store / live users)

- **Fractional modules are not supported.** Clients must not rely on `*_FRAC` cues, atomic clip timelines, or `postFractionalPlan`.
- **Use only legacy monolithic cues** where the server exposes them: `INT_GEN_1` / `INT_MORN_1`, `PB1`–`PB5`, `BS1`–`BS10`, `IM2`–`IM10`, `NF1`–`NF10`, plus shared cues from `cues.json` (e.g. `OH`, `VC`, `RT`, `GB`).
- `expandFractionalCues` does **nothing** (pass-through).
- `postFractionalPlan` returns **403**.
- Catalog JSON merged for GET `/catalogs` comes from `cues.json` + `*_legacy.json` files (e.g. `introduction_legacy.json`, `nostril_focus_legacy.json`).

## Development — `imaginedev-e5fd3` (`.firebaserc` → `dev`)

- **Fractional is supported.** Use **fractional** catalog entries and composition wherever this repo defines them (e.g. `INT_FRAC`, `PB_FRAC`, `BS_FRAC_UP` / `BS_FRAC_DOWN`, `IM_FRAC`, `NF_FRAC`).
- AI / `postMeditations` use fractional cue ids from `cueBuilder`, then `expandFractionalCues` expands into second-precision / atomic clips as designed.
- `postFractionalPlan` is **enabled** for runtime fractional plans.
- Catalog JSON merged for GET `/catalogs` comes from `cues.json` + non-legacy files (`introduction.json`, `body_scan.json`, `perfect_breath.json`, `i_am_mantra.json`, `nostril_focus.json` with `NF_FRAC`, etc.).

**Rule of thumb:** Production = **old monolithic only**. Dev = **fractional only** (no merged legacy row for the same module in GET `/catalogs` — legacy files are not loaded on dev).

---

| | Production `imagine-c6162` | Dev `imaginedev-e5fd3` |
|---|---------------------------|-------------------------|
| Fractional | Off | On |
| GET `/catalogs` | `*_legacy.json` | Fractional JSON files |
| Nostril in catalog | `NF1`…`NF10` | `NF_FRAC` (+ expansion) |

**Deploy**

```bash
# Production (monolithic only)
npx firebase deploy --only functions --project imagine-c6162

# Dev (fractional)
npx firebase deploy --only functions --project imaginedev-e5fd3
```

**Local emulator:** `GCLOUD_PROJECT` may be unset or match whichever project you emulate; align emulator project with the behavior you want to test.

**Bucket:** Audio paths still point at `gs://imagine-c6162.appspot.com/...` unless you change `CONTENT_STORAGE_BUCKET` in code; dev and prod Functions can share the same bucket for assets.
