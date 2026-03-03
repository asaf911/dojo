# Auth Feature

## Overview

Unified authentication for Google, Apple, and Email. Sign-up vs sign-in is determined by the auth result (Firebase/backend), not by which screen the user is on.

## Flow

1. User taps Google/Apple or completes email verification.
2. **Social:** Credential is obtained and passed to `UserIdentityManager.linkWithSocialCredential`.
3. **Link path:** If anonymous user exists, link credential. On `credentialAlreadyInUse` (17025), fall back to direct sign-in.
4. **Direct path:** Used when no anonymous user or link fails with credential-in-use.
5. **Analytics:** `sign_up` for new accounts, `sign_in` for returning. `auth_error` on failure.
6. **Post-auth:** Identity transition, handlePostAuthentication, navigate to main.

## Console Log Tags

- `📊 [AUTH:SOCIAL]` — Social auth (Google, Apple)
- `📊 [AUTH:EMAIL]` — Email code flow
- `📊 [AUTH:EVENT]` — Analytics events
- `📊 [AUTH:UI]` — Screen-level events
- `📊 [ID:SOCIAL]` — UserIdentityManager credential linking
