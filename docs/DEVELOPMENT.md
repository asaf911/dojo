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
- Firebase Storage paths use `imaginedev-e5fd3.appspot.com`

When OFF (default): the app uses production (`imagine-c6162`).

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

## Firebase Functions: Storage Bucket

The functions code uses `GCLOUD_PROJECT` (set by Firebase at runtime) to determine the storage bucket. Each deployment automatically uses its project's bucket:

- Deploy to dev → functions use `imaginedev-e5fd3.appspot.com`
- Deploy to prod → functions use `imagine-c6162.appspot.com`

No code changes are needed when switching deploy targets.

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
