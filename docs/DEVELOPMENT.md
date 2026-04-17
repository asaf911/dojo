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

## Firebase Hosting (marketing site)

The public marketing site lives under `web/` (Vite). Build output is `web/dist/`. [`firebase.json`](../firebase.json) configures Hosting with a **predeploy** that runs `npm ci` and `npm run build` in `web/` so each deploy uploads a fresh build.

**Important:** Use `--only hosting` so website deploys never push Cloud Functions.

| Command (repo root) | Action |
|---------------------|--------|
| `npm run deploy:hosting:dev` | `firebase use dev` then deploy Hosting to **`imaginedev-e5fd3`** |
| `npm run deploy:hosting:prod` | `firebase use default` then deploy Hosting to **`imagine-c6162`** |

Equivalent manual commands:

```bash
firebase use dev && firebase deploy --only hosting    # staging
firebase use default && firebase deploy --only hosting  # production
```

**First-time setup:** run `firebase login` on the machine that deploys. The first successful Hosting deploy attaches the default Hosting site to the selected project. After deploy to dev, the site is available at `https://imaginedev-e5fd3.web.app` (and `https://imaginedev-e5fd3.firebaseapp.com`).

### Support form (`/support/`) and `/api/support`

The marketing support page POSTs to **`/api/support`**. Firebase Hosting rewrites that path to the **`supportContact`** Cloud Function, which sends mail through **Google Workspace SMTP** (Gmail: `smtp.gmail.com`) using a **relay Workspace user** with a Gmail **App Password** (not your normal password). Messages are delivered to **`SUPPORT_INBOX_EMAIL`** (e.g. `support@medidojo.com`); the visitor’s address is set as **`Reply-To`**.

**Secrets** (create in Google Cloud Secret Manager for each Firebase project that should send mail; bind on deploy):

| Secret | Example value |
|--------|----------------|
| `WORKSPACE_SMTP_USER` | Full email of the relay user (e.g. `website@medidojo.com`) |
| `WORKSPACE_SMTP_APP_PASSWORD` | 16-character App Password for that user |
| `SUPPORT_INBOX_EMAIL` | `support@medidojo.com` |

Set from repo root (replace project if needed):

```bash
firebase use dev
echo -n 'website@medidojo.com' | firebase functions:secrets:set WORKSPACE_SMTP_USER --data-file=-
echo -n 'xxxx xxxx xxxx xxxx' | firebase functions:secrets:set WORKSPACE_SMTP_APP_PASSWORD --data-file=-
echo -n 'support@medidojo.com' | firebase functions:secrets:set SUPPORT_INBOX_EMAIL --data-file=-
```

Then deploy functions (and hosting if the form or rewrite changed): `firebase deploy --only functions,hosting`.

**Local Vite:** `web/vite.config.ts` proxies `POST /api/support` to `https://imaginedev-e5fd3.web.app` so the form can be tested from `npm run dev` after dev Hosting + functions are deployed with secrets.

**Rate limiting:** `supportContact` uses a small **in-memory** limit per Cloud Function instance (no Firestore). It reduces accidental bursts; for stronger abuse protection, add reCAPTCHA or similar later.

**Dev placeholders:** If `WORKSPACE_SMTP_USER` / `WORKSPACE_SMTP_APP_PASSWORD` are still placeholder values, the endpoint returns HTTP 500 with “Could not send message” until you set real Workspace App Password secrets and redeploy `supportContact`.

**Production:** repeat `firebase functions:secrets:set` for the **`default`** (`imagine-c6162`) project before deploying prod hosting, or the form will return a configuration error from the function.

**Production cutover:** when the site is ready, run `npm run deploy:hosting:prod` (or the manual prod command above). Add a **custom domain** under Firebase Console → Hosting for the prod project; at GoDaddy, add the DNS records Firebase displays.

**CI note:** If you add automated Hosting deploys, align the runner’s Node version with local development so `npm ci` / Vite builds behave consistently.

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

## AI Agent / Cursor Response Convention

At the end of each response that involves code or config changes, include a short **environment status**:

- **Dev** — updated / will need deploy / not affected
- **Prod** — updated / will need deploy / not affected
- **Content bucket** — updated / not affected
- **iOS** — updated / not affected

Example: `Env: Dev + Prod functions need deploy; Content bucket unchanged; iOS unchanged.`

## Configuration Reference

- **`.firebaserc`** — Defines project aliases (`default`, `dev`).
- **`firebase.json`** — Cloud Functions plus **Hosting** (`public`: `web/dist`, `predeploy` builds `web/`).
- **`package.json` (repo root)** — `deploy:hosting:dev` and `deploy:hosting:prod` for marketing site Hosting only.
- **`functions/package.json`** — Contains `deploy:dev`, `deploy:prod`, `deploy:dev-to-prod` scripts.
- **`ios/imagine/Shared/Constants/Configuration.swift`** — Runtime URLs and `activeServerPath` based on `useDevServer` flag.
- **`ios/imagine/Shared/Helpers/User Storage/UserStorageProtocol.swift`** — `UserStorageKey.useDevServer` persists the toggle state.
