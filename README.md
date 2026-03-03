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
