# 🎯 Watch App Lifecycle Management Rules

## Overview

This document describes the implemented lifecycle rules for optimal watch app management, ensuring reliable heart rate monitoring while preserving battery life.

## 📋 Implemented Rules

### Rule 1: Phone App Launch → Watch App Activation
**When the phone app launches, the watch app launches/comes back from background and BPM tracking is on**

#### Implementation:
- **AppDelegate.swift**: 
  - On `didFinishLaunchingWithOptions`, calls `PhoneConnectivityManager.shared.wakeUpWatchApp()`
  - On `applicationWillEnterForeground`, wakes up watch app again
  
- **PhoneConnectivityManager.swift**:
  - `wakeUpWatchApp()`: Sends wake command and starts background monitoring
  - Uses both `sendMessage` and `transferUserInfo` for reliability

- **WatchConnectivityManager.swift**:
  - Handles `wakeUp` command
  - Sends confirmation back to iPhone
  - Relies on HKWorkoutSession for background execution

### Rule 2: Practice Playing → Continuous BPM Monitoring
**As long as a practice is playing, the watch measures BPM and the phone receives it, even if apps go to background**

#### Implementation:
- **PlayerScreenView.swift**:
  - Calls `startIntensiveHeartRateMonitoring()` when practice starts
  - Maintains monitoring even when app goes to background

- **WatchHealthKitManager.swift**:
  - Uses `HKWorkoutSession` for background heart rate access
  - Workout session automatically keeps app active in background
  - Continues heart rate queries even when app state is background

- **Background Execution**:
  - Watch app Info.plist includes `workout-processing` background mode
  - HKWorkoutSession provides background execution privileges
  - No need for manual app lifecycle management

### Rule 3: No Practice + Phone Background → Watch Sleep
**When there is no meditation practice playing and phone app is in background, turn off the watch app**

#### Implementation:
- **AppDelegate.swift**:
  - `applicationDidEnterBackground`: Checks if practice is playing
  - If no practice: calls `PhoneConnectivityManager.shared.stopAllMonitoring()`
  - If practice active: maintains watch monitoring

- **PhoneConnectivityManager.swift**:
  - `stopAllMonitoring()`: Sends command to stop all watch monitoring
  - Also called after practice ends if app is in background

- **WatchConnectivityManager.swift**:
  - Handles `stopAllMonitoring` command
  - Stops intensive and background monitoring
  - App naturally goes to background when no workout session is active

## 📊 State Flow Diagram

```
┌─────────────────────┐
│ iPhone App Launch   │
└──────────┬──────────┘
           ▼
┌─────────────────────┐
│ Wake Watch App      │
│ Start BG Monitoring │
└──────────┬──────────┘
           ▼
┌─────────────────────┐     ┌─────────────────────┐
│ Practice Started    │────▶│ Intensive HR        │
│                     │     │ Monitoring Active   │
└─────────────────────┘     └──────────┬──────────┘
                                       ▼
                            ┌─────────────────────┐
                            │ Practice Ended      │
                            └──────────┬──────────┘
                                       ▼
                            ┌─────────────────────┐
                            │ App in Background?  │
                            └──────┬───────┬──────┘
                                  Yes      No
                                   ▼        ▼
                        ┌──────────────┐  ┌──────────────┐
                        │ Stop All     │  │ Continue BG  │
                        │ Monitoring   │  │ Monitoring   │
                        └──────────────┘  └──────────────┘
```

## 🔧 Key Components

### Watch App Commands
- **`wakeUp`**: Activates watch app and starts background monitoring
- **`startBackgroundMonitoring`**: Ensures background monitoring is active
- **`startHeartRateMonitoring`**: Starts intensive monitoring for practice
- **`stopHeartRateMonitoring`**: Stops intensive monitoring
- **`stopAllMonitoring`**: Stops all monitoring and allows watch sleep

### Battery Optimization
- Background monitoring: 5-minute intervals with infrared LED
- Intensive monitoring: Real-time with green LED during practice only
- App sleeps when not needed (no practice + phone in background)

### Reliability Features
- Dual message delivery (immediate + guaranteed)
- Command acknowledgments
- Retry mechanism for failed commands
- Wake up confirmation from watch

## 📱 Usage Scenarios

### Scenario 1: User Opens App
1. iPhone app launches
2. Watch app wakes up automatically
3. Background BPM monitoring starts (5-min intervals)
4. User sees occasional heart rate updates

### Scenario 2: User Starts Practice
1. Practice begins on iPhone
2. Watch switches to intensive monitoring
3. Real-time BPM data flows to iPhone
4. Monitoring continues even if user lowers wrist

### Scenario 3: Practice Ends, User Switches Apps
1. Practice completes
2. iPhone app goes to background
3. Watch app stops all monitoring
4. Battery is preserved

### Scenario 4: User Returns to App
1. iPhone app comes to foreground
2. Watch app wakes up again
3. Background monitoring resumes
4. Ready for next practice session

## 🔍 Debugging

### Expected Logs

**iPhone App Launch:**
```
AppDelegate: Wake up watch app when iPhone app launches
PhoneConnectivityManager: 🔔 Waking up watch app
PhoneConnectivityManager: 📤 Wake up command sent
```

**Watch Response:**
```
WatchConnectivityManager: 🎯 Processing command: wakeUp
WatchConnectivityManager: 🔔 Wake up command received
WatchHealthKitManager: 🔄 Ensuring background monitoring is active
```

**Practice Start:**
```
PhoneConnectivityManager: 🚀 Starting intensive monitoring
WatchHealthKitManager: 🚀 Starting intensive monitoring for practice session
```

**App Background (No Practice):**
```
AppDelegate: App entering background with no active practice - stopping watch monitoring
PhoneConnectivityManager: 💤 Stopping all monitoring and allowing watch to sleep
WatchConnectivityManager: 💤 Stopping all monitoring
```

## ✅ Benefits

1. **Automatic Operation**: No user intervention required
2. **Optimal Battery Usage**: Watch only active when needed
3. **Reliable Monitoring**: Guaranteed BPM during all practices
4. **Smart Lifecycle**: Adapts to app and practice state

## 🚀 Testing

1. Launch iPhone app → Verify watch wakes up
2. Start practice → Verify intensive monitoring begins
3. Lock phone during practice → Verify BPM continues
4. End practice and switch apps → Verify watch stops monitoring
5. Return to app → Verify watch wakes up again 