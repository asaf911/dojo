# Dojo

Monorepo for the Dojo meditation app.

## Structure

- **ios/** — iOS app (Xcode project)
- **functions/** — Firebase Cloud Functions (server)

## Setup

### iOS
Open `ios/imagine.xcodeproj` in Xcode.

### Firebase
```bash
cd functions && npm install
firebase deploy
```

## Development

We use two Firebase projects (prod + dev). The iOS app has a "Use Dev Server" toggle in Dev Mode (7 taps on Settings title) to switch backends at runtime.

**Deploy commands** (from `functions/`):
- `npm run deploy:dev` — Deploy to dev project
- `npm run deploy:prod` — Deploy to production
- `npm run deploy:dev-to-prod` — Promote dev to production after validation

See [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md) for the full workflow and configuration.
