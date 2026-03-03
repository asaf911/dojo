# Heart Rate Analytics - Clean Mixpanel Tracking

## Architecture

One HR event (`heart_rate_session_complete`) linked to session events via a shared `session_id`, with People properties enabling cohort analysis.

### Event Flow

```
Onboarding
  onboarding_heart_rate_result      -> sets People: hr_onboarding_result
  onboarding_mindful_minutes_result -> sets People: mindful_minutes_onboarding_result

Session
  session_start       (includes session_id, hr_feature_enabled)
  session_complete    (includes session_id, hr_feature_enabled)

Heart Rate
  heart_rate_session_complete (includes session_id, hr_session_number)
    -> sets People: has_measured_hr, first_session_start_hr (setOnce)
    -> sets People: latest_session_start_hr, last_hr_primary_source
    -> increments People: total_hr_sessions
```

## Event: `heart_rate_session_complete`

Single comprehensive event fired once per session by `PracticeBPMTracker.stopTracking()`.

### Core Parameters (always present)
| Parameter | Type | Description |
|---|---|---|
| `session_id` | string | Links to session_start / session_complete |
| `watch_paired` | boolean | Whether Apple Watch is paired |
| `practice_title` | string | Title of the practice |
| `practice_category` | string | Category (e.g., "relax", "focus", "custom" for custom meditations) |
| `practice_duration_minutes` | integer | Duration in minutes |
| `content_type` | string | Meditation type: "pre_recorded", "path_step", "custom_meditation" |
| `watch_status` | string | "not_paired", "not_connected", "not_live", "live_mode" |
| `watch_connected` | boolean | Whether watch is connected |
| `live_mode_active` | boolean | Whether live mode is active |

**Note:** `getCurrentPracticeDetails()` uses AudioPlayerManager for pre-recorded/path and SessionContextManager for custom meditations, so all three types get full practice metadata.

### Success Parameters (`measurement_success = true`)
| Parameter | Type | Description |
|---|---|---|
| `measurement_success` | boolean | `true` |
| `start_heart_rate` | integer | Starting BPM (avg of first 3 readings) |
| `end_heart_rate` | integer | Ending BPM (avg of last 3 readings) |
| `average_heart_rate` | integer | Average BPM across session |
| `heart_rate_change_percent` | float | % change start to end (1 decimal) |
| `heart_rate_impact` | string | "steady", "subtle_relaxation", "regular_relaxation", "deep_relaxation", "increased" |
| `sample_count` | integer | Number of HR samples collected |
| `measurement_duration_seconds` | integer | Duration of measurement |
| `heart_rate_range` | string | "below_60", "60_to_100", "100_to_140", "140_to_180", "above_180" |
| `measurement_quality` | string | "poor", "fair", "good", "excellent" |
| `hr_session_number` | integer | Nth successful HR session for this user (1-indexed) |
| `primary_source` | string | "watch", "airpods", "none" |
| `preferred_source` | string | "watch", "airpods", "none" |
| `sources_used` | string | Available sources |
| `fallback_used` | boolean | Whether source switching occurred |
| `first_sample_latency_ms` | integer | Time to first HR reading (if available) |

### Failure Parameters (`measurement_success = false`)
| Parameter | Type | Description |
|---|---|---|
| `measurement_success` | boolean | `false` |
| `error_reason` | string | See error codes below |

### Error Codes
- `watch_not_paired` - No Apple Watch paired
- `watch_not_connected` - Watch not connected
- `permission_denied` - HealthKit permission denied
- `no_data_received` - No heart rate data received
- `insufficient_samples` - Not enough samples
- `session_timeout` - Monitoring timed out (15s+)
- `watch_app_not_installed` - Watch app not installed
- `live_mode_not_active` - Live mode not active
- `unknown_error` - Other errors

## People Properties

### Set During Onboarding
| Property | Type | Set When |
|---|---|---|
| `hr_onboarding_result` | string | "prompted" or "skipped" |
| `mindful_minutes_onboarding_result` | string | "authorized", "denied", "skipped", "already_authorized" |
| `onboarding_goal` | string | User's selected goal |
| `onboarding_hurdle` | string | User's selected hurdle |

### Set on Successful HR Measurement
| Property | Type | Method |
|---|---|---|
| `has_measured_hr` | boolean | setOnce (true) |
| `first_session_start_hr` | integer | setOnce (baseline resting HR) |
| `latest_session_start_hr` | integer | set (most recent start HR) |
| `last_hr_primary_source` | string | set ("watch" or "airpods") |
| `last_hr_measurement_at` | date | set |
| `total_hr_sessions` | integer | increment |
| `total_hr_watch_sessions` | integer | increment (if Watch) |
| `total_hr_airpods_sessions` | integer | increment (if AirPods) |
| `total_hr_fallback_sessions` | integer | increment (if source switched) |

## Session Events (enriched)

`session_start` and `session_complete` now include:
- `session_id` - shared identifier to join with `heart_rate_session_complete`
- `hr_feature_enabled` - boolean indicating if HR tracking was active for this session

## Deleted Events

The following events have been removed:
- `healthkit_authorization_result` (was in HealthKitManager)
- `healthkit_mindful_minutes_result` (was in HealthKitManager)
- `healthkit_heart_rate_result` (was in HealthKitManager)
- `healthkit_authorization_status_checked` (was in HealthKitManager)
- `healthkit_mindfulness_session_saved` (was in HealthKitManager)
- `healthkit_mindfulness_session_save_failed` (was in HealthKitManager)
- `watch_permission_result` (was in WatchAnalyticsManager)
- `watch_insights_summary` (was in WatchAnalyticsManager)
- `onboarding_healthkit_connected` (legacy, was in OnboardingAnalytics)

The following were silenced:
- `watch_status_checked` no longer auto-fires on every app foreground

## Key Mixpanel Queries

### HR Permission Funnel (Onboarding -> Measurement)
```
Funnel: onboarding_heart_rate_result (result = "prompted")
     -> heart_rate_session_complete (measurement_success = true)
```

### HR Improvement Over Time
```
heart_rate_session_complete WHERE measurement_success = true
GROUP BY hr_session_number
AVG(heart_rate_change_percent)
```

### Retention by HR Usage
```
Cohort: has_measured_hr = true vs false
Measure: 7-day / 30-day retention
```

### Most Relaxing Content
```
heart_rate_session_complete WHERE measurement_success = true
GROUP BY practice_category
AVG(heart_rate_change_percent) ORDER ASC (more negative = more relaxing)
```

### HR by Meditation Type (content_type)
```
heart_rate_session_complete WHERE measurement_success = true
GROUP BY content_type
AVG(heart_rate_change_percent)
```

## Meditation Types Quick Reference

All three meditation types send `heart_rate_session_complete` with full practice metadata to Mixpanel.

| Aspect | Pre-recorded | Path | Custom |
|--------|:------------:|:----:|:------:|
| `session_id` | ✅ | ✅ | ✅ |
| `startNewSession` | ✅ | ✅ | ✅ |
| `stopTracking` | ✅ | ✅ | ✅ |
| HR data (BPM, etc.) | ✅ | ✅ | ✅ |
| People updates | ✅ | ✅ | ✅ |
| `practice_title` | ✅ | ✅ | ✅ |
| `practice_category` | ✅ | ✅ | ✅ (`"custom"`) |
| `practice_duration_minutes` | ✅ | ✅ | ✅ |
| `content_type` | `pre_recorded` | `path_step` | `custom_meditation` |

**Data source:** Pre-recorded/path → `AudioPlayerManager.selectedFile`. Custom → `SessionContextManager.currentContext`.
