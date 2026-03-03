# Imagine Meditation

## About
Imagine Meditation is a simple and intuitive meditation app designed to help users relax and focus. It offers a selection of audio files categorized into relaxation, focus, and imagination themes.

## Features
- Customizable audio selections for different meditation needs.
- Timer countdown for each meditation session.
- Play/Pause and Rewind functionality for better control.
- Background play support for uninterrupted sessions.

## Recent Changes

### Dual-Tracking Install/Reinstall System

Implemented a robust dual-tracking system that combines immediate Firebase-based tracking with AppsFlyer attribution enrichment:

#### **Phase 1: Early Firebase Tracking**
- Tracks install/reinstall events **immediately** on app launch with Firebase UID
- No delays or dependencies on external callbacks
- Ensures events are captured even if AppsFlyer fails
- Includes device info, app version, and timing data

#### **Phase 2: AppsFlyer Attribution Enrichment**
- Enriches early events with attribution data when AppsFlyer callback fires
- Adds campaign, media source, and channel information
- Provides comprehensive attribution for marketing analysis

**Benefits of this dual approach:**
1. **Immediate Tracking**: Events fire within seconds of app launch with Firebase UID
2. **No Data Loss**: Fallback ensures events are captured even if AppsFlyer fails
3. **Rich Attribution**: AppsFlyer enriches events with marketing attribution
4. **Consistent Identity**: All events use the same Firebase UID across vendors from day 1
5. **Unified Mixpanel Identity**: All users (anonymous & authenticated) use Firebase UID as distinct_id
6. **Best Practices**: Follows mobile analytics industry standards

**What you'll see in Mixpanel:**
- `install` / `reinstall` events with Firebase UID as distinct_id (not device_id)
- `install_attribution` / `reinstall_attribution` events with AppsFlyer data (when available)
- User properties: `first_seen`, `install_method`, `install_source`
- **Consistent identity**: Anonymous users, guest users, and authenticated users all use Firebase UID

**Event Structure:**
```javascript
// Early tracking event (uses Firebase UID as distinct_id)
{
  "event": "install",
  "distinct_id": "firebase_uid_123",  // ← Firebase UID, not device_id
  "properties": {
    "user_id": "firebase_uid_123",
    "tracking_method": "early_firebase",
    "app_version": "1.2.3",
    "device_model": "iPhone15,2",
    "is_genuine_first_install": true
  }
}

// Attribution enrichment event (when AppsFlyer data available)
{
  "event": "install_attribution",
  "distinct_id": "firebase_uid_123",  // ← Same Firebase UID
  "properties": {
    "user_id": "firebase_uid_123",
    "tracking_method": "appsflyer_enrichment",
    "media_source": "google_ads",
    "campaign": "spring_meditation",
    "is_first_launch_af": true
  }
}
```

**To test the implementation:**
1. Uninstall the app completely
2. Build and install a fresh version  
  3. Launch the app - you'll see immediate `install` event in Mixpanel Live View
  4. Wait for AppsFlyer processing - you'll see `install_attribution` event
  5. Reinstall to see `reinstall` and `reinstall_attribution` events

#### **Identity Management Improvements**

**Unified Firebase UID Strategy:**
- All users (anonymous, guest, authenticated) use Firebase UID as Mixpanel distinct_id
- No more device_id fragmentation across user states
- Consistent identity from app launch through authentication
- Seamless tracking across user journey without identity switches

**Timeline:**
1. **App Launch**: Check existing Firebase user → Validate user exists on server
2. **Identity Setting**: Set Mixpanel identity ONLY with validated Firebase UID
3. **Install Event**: Tracked with validated Firebase UID as distinct_id (not device_id)
4. **Guest/Signup**: Same validated Firebase UID maintained through authentication
5. **All Events**: Consistent Firebase UID across all analytics platforms

**Critical Fix - Single Identity Per Session:**
- **Validate First**: Check Firebase user exists on server before setting Mixpanel identity
- **Single Identity**: Only one Mixpanel distinct_id set per app session
- **No Fragmentation**: Prevents multiple UIDs when cached users are invalid
- **Session Guards**: Prevents duplicate identity setting within same session

For any questions: asaf911@gmail.com
