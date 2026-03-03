# Watch & Heart Rate Analytics Guide

## Overview

Heart rate analytics uses a single comprehensive event (`heart_rate_session_complete`) linked to session events via a shared `session_id`. All redundant and legacy events have been removed.

## Events

### `heart_rate_session_complete`

Fired once per meditation session by `PracticeBPMTracker.stopTracking()`. Contains all HR data for the session.

See [HEART_RATE_ANALYTICS_IMPLEMENTATION.md](HEART_RATE_ANALYTICS_IMPLEMENTATION.md) for full parameter reference.

### `watch_status_checked`

Tracks watch pairing and connectivity status. Available as an on-demand call via `WatchAnalyticsManager.shared.trackWatchStatus()` but does NOT auto-fire.

**Parameters:**
- `watch_paired` (boolean)
- `watch_connectivity_supported` (boolean)
- `watch_app_installed` (boolean) - only when paired
- `watch_reachable` (boolean) - only when paired
- `watch_session_activated` (boolean) - only when paired

### `watch_heart_rate_retry`

Tracks when user manually retries HR monitoring.

**Parameters:**
- `watch_paired` (boolean)
- `watch_connected` (boolean)
- `retry_initiated_by_user` (boolean): always `true`
- `practice_title` (string, optional)
- `practice_category` (string, optional)
- `practice_duration_minutes` (integer, optional)

## Files

| File | Responsibility |
|---|---|
| `WatchAnalyticsManager.swift` | Sends `heart_rate_session_complete`, manages People properties |
| `PracticeBPMTracker.swift` | Collects HR data, calls `trackHeartRateSession()` on stop |
| `SessionContextManager.swift` | Generates `session_id`, provides session context |
| `OnboardingAnalytics.swift` | Sets `hr_onboarding_result` People property |

## Deleted Events & Methods

These have been fully removed from the codebase:
- `healthkit_authorization_result`
- `healthkit_mindful_minutes_result`
- `healthkit_heart_rate_result`
- `healthkit_authorization_status_checked`
- `healthkit_mindfulness_session_saved`
- `healthkit_mindfulness_session_save_failed`
- `watch_permission_result`
- `watch_insights_summary`
- `onboarding_healthkit_connected`
- `trackPracticeStartAnalytics()` (deprecated method)
- `trackPracticeCompleteAnalytics()` (deprecated method)
- `trackHeartRateError()` (deprecated method)
- `trackPermissionRequest()` (deprecated method)
- `trackInsightsSummary()` / `trackInsightsViewed()` (deprecated methods)
- `testSimplifiedTracking()` (test method)
- Auto-fire of `watch_status_checked` on every app foreground
