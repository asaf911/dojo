# Development Environment

This document describes the dev/production environment model for the Dojo project. It is intended for developers and AI agents working in this repository.

## Environment Model

We use **two Firebase projects** with the same codebase:

| Project | Alias | Purpose |
|---------|-------|---------|
| `imagine-c6162` | `default` | Production |
| `imaginedev-e5fd3` | `dev` | Development / testing |

The deploy target is selected via `firebase use`. There is no separate codebase or branch for dev—the same `functions/` code deploys to both projects.

## iOS: Dev Server Toggle

The iOS app can switch between production and dev backends at **runtime** via a toggle in Dev Mode:

1. **Enable Dev Mode:** Tap the "My Settings" title 7 times in Settings.
2. **Toggle "Use Dev Server":** When Dev Mode is active, a "Server" card appears. Toggle "Use Dev Server" ON to use the dev Firebase project (Cloud Functions + Storage). Toggle OFF for production.

When "Use Dev Server" is ON:
- Cloud Functions URLs point to `us-central1-imaginedev-e5fd3.cloudfunctions.net`
- Content (MP3s, images, audioFiles.json, pathSteps.json) is always fetched from the prod bucket (`imagine-c6162.appspot.com`)

When OFF (default): the app uses production (`imagine-c6162`) for both Cloud Functions and content.

## Deploy Commands

From the `functions/` directory:

| Command | Action |
|---------|--------|
| `npm run deploy:dev` | Deploy functions to **dev** project (`imaginedev-e5fd3`). Requires dev project on Blaze plan. |
| `npm run deploy:prod` | Deploy functions to **production** project (`imagine-c6162`) |
| `npm run deploy:dev-to-prod` | Switch to default project and deploy—use after validating on dev to promote to production |

### Typical Workflow

1. Make changes to `functions/` code.
2. Deploy to dev: `cd functions && npm run deploy:dev`
3. In the iOS app, enable Dev Mode and turn on "Use Dev Server".
4. Test the changes against the dev backend.
5. When satisfied, promote to production: `cd functions && npm run deploy:dev-to-prod`
6. Turn off "Use Dev Server" in the app to use production again.

## Single Content Bucket

All content (MP3s, images, `audioFiles.json`, `pathSteps.json`) lives in the **production bucket** (`imagine-c6162.appspot.com`). Both dev and prod Cloud Functions return media URLs pointing to this bucket. The iOS app always fetches content from prod, regardless of the "Use Dev Server" toggle.

The toggle only affects which Cloud Functions backend is called (getCatalogs, postMeditations, postAIRequest). The dev bucket is no longer used for content.

## Firebase Functions: Catalog Media URLs

The functions code uses a fixed content bucket for catalog media URLs:

- Both dev and prod deployments return `gs://imagine-c6162.appspot.com/...` for background music, cues, binaural beats, etc.

**Note:** The dev Firebase project (`imaginedev-e5fd3`) must be on the Blaze (pay-as-you-go) plan to deploy Cloud Functions. If `deploy:dev` fails with an API error, upgrade at: https://console.firebase.google.com/project/imaginedev-e5fd3/usage/details

## Console Logging

The iOS app prints `[Server]`-tagged logs so you can validate which server is in use. Filter the Xcode console by `[Server]` to see:

- `[Server][Config]` — Active server at app launch and when toggled in Dev Mode
- `[Server][Catalogs]` — Catalogs fetch (includes `server=Production` or `server=Dev`)
- `[Server][Meditations]` — Manual/AI meditation creation
- `[Server][AI]` — AI request endpoint
- `[Server][Storage]` — Audio files fetch from Firebase Storage
- `[Server][Path]` — Path steps fetch

## Configuration Reference

- **`.firebaserc`** — Defines project aliases (`default`, `dev`).
- **`functions/package.json`** — Contains `deploy:dev`, `deploy:prod`, `deploy:dev-to-prod` scripts.
- **`ios/imagine/Shared/Constants/Configuration.swift`** — Runtime URLs and `activeServerPath` based on `useDevServer` flag.
- **`ios/imagine/Shared/Helpers/User Storage/UserStorageProtocol.swift`** — `UserStorageKey.useDevServer` persists the toggle state.
