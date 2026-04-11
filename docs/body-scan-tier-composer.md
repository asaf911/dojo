# Body scan tier composer (BS_FRAC)

**Purpose:** Single reference for agents working on `body_scan_fractional` without reading the whole codebase.

## Where the code lives

| Area | File |
|------|------|
| Tier plan + gaps + entry stripping | `functions/src/bodyScanTierPlan.ts` |
| Generic fractional (NF/IM) + **inline expansion** | `functions/src/fractionalComposer.ts` |
| HTTP `POST /postFractionalPlan` | `functions/src/index.ts` (handler + request parsing) |
| Catalog | `functions/catalogs/body_scan_fractional.json` |
| Dev UI → API | `ios/imagine/Features/FractionalModules/*` (MVVM; see `.cursorrules`) |

**Module intro (1–4 min vs first on timeline):** [`docs/fractional-module-intro-rule.md`](./fractional-module-intro-rule.md) — applies to BS and every other fractional module.

## Product vs composer direction (do not invert again)

| Product label | Scan direction | Composer `bodyScanDirection` |
|---------------|----------------|------------------------------|
| Body Scan **Down** | head → feet | `"up"` |
| Body Scan **Up** | feet → head | `"down"` |

Cue → composer mapping for expansion: `BS_FRAC_DOWN` → `"up"`, `BS_FRAC_UP` → `"down"` (`resolveBodyScanExpandDirection` in `fractionalComposer.ts`).  
iOS picker “Up” sends API `"down"`; “Down” sends `"up"` (see `FractionalModules+ViewModel`).

## Roles in the catalog

- **intro** — `introVariant` `short` | `long`; can play both in order (short then long).
- **entry** — `entryScanEnd` `top`|`bottom`, `entryTier` matches first scanned zone’s tier; **replaces** the first matching instruction (see `stripEntryAnchorInstruction`).
- **instruction** — `macroZone` 1–3, `bodyTier`, `orderUp` / `orderDown`.
- **integration** — outro lines; `integrationOrder`; treated like body parts for **equal silence** slots.

## Silence / gaps

- Variable gap count = **`nBody + nIntegration`** (one slot after each part, including after the last).
- Budget = `durationSec − audio − bridges`; split with **`distributeGapsEqual`** (integer fair split).
- **Minimum** silence for feasibility: `minVariableSilenceBudget` (stricter when integrations > 0).
- **Bridges:** `BRIDGE_SEC` (7s) after each intro and after entry (if present). This is **only** spacing between intro/entry segments — not the same as **`FRACTIONAL_FIRST_SPEECH_OFFSET_SEC`** (global 7s lead-in before the first voice when `atTimelineStart` is true; see [`fractional-module-intro-rule.md`](./fractional-module-intro-rule.md)).

## API (`postFractionalPlan`)

Body-scan modules: `BS_FRAC`, `BS_FRAC_UP`, `BS_FRAC_DOWN`.

- `bodyScanDirection` optional unless `BS_FRAC`; UP/DOWN moduleIds **override** direction.
- `introShort` / `introLong` booleans; legacy `introStyle` if neither boolean sent.
- `atTimelineStart` — optional boolean. When **true**, short/long framing intros are allowed even if `durationSec < 300`. Inline expansion sets this only when the fractional block is at **meditation start** (second 0), is the **first fractional row**, and **no non-fractional cue** precedes it (see `fractional-module-intro-rule.md`).
- `includeEntry` — **default `true`** when omitted for body scan; send `false` for instruction-only first anchor.

## Inline expansion (`expandFractionalCues`)

Used by `postMeditations` / AI paths. Body scan uses **fixed** composer flags: short intro only, long off, **entry on** (`fractionalComposer.ts`). `atTimelineStart` is set in `expandFractionalCues` when the cue is the **first fractional module row** in the request cue list (not “trigger is start”). To change defaults, edit that call site.

## Tests

`functions/src/bodyScanTierPlan.test.ts` — run `npm test` in `functions/`.

## Related doc

`docs/fractional-module-composition.md` — generic two-phase fractional modules (not tier-specific).
