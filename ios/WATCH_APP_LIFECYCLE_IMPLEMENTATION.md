# Watch App Lifecycle Implementation

## Overview

This implementation provides precise control over the watch app's visibility and lifecycle according to your requirements:

1. **Phone app launch** → watch app launches and becomes visible
2. **Phone app goes to background** → watch app goes to background  
3. **Practice is running** → watch app stays running (overrides background rule)
4. **Practice ends + phone in foreground** → watch app stays in foreground

## How It Works

### Automatic Launch Technology
- **Background Workout Sessions** - Creates a persistent background session that allows remote app launching
- **Background App Refresh** - Schedules refresh events to keep app available for wake-up
- **WKExtension APIs** - Controls app visibility and extended runtime
- **Local Notifications** - Brings app to foreground when commanded

### Implementation Components

#### 1. Phone App (AppDelegate.swift)
```swift
// App launch → automatically wake up watch app
func application(_ application: UIApplication, didFinishLaunchingWithOptions...) {
    PhoneConnectivityManager.shared.wakeUpWatchApp()
}

// Foreground → notify watch to stay visible
func applicationWillEnterForeground(_ application: UIApplication) {
    PhoneConnectivityManager.shared.notifyPhoneEnteredForeground()
    PhoneConnectivityManager.shared.wakeUpWatchApp()
}

// Background → check if practice active
func applicationDidEnterBackground(_ application: UIApplication) {
    PhoneConnectivityManager.shared.notifyPhoneEnteredBackground()
    
    if !isPlayingPractice {
        PhoneConnectivityManager.shared.stopAllMonitoring() // Allows watch to sleep
    }
}
```

#### 2. Phone Connectivity Manager (PhoneConnectivityManager.swift)
- **wakeUpWatchApp()** - sends wake command + starts background monitoring
- **notifyPhoneEnteredForeground()** - tells watch phone is in foreground  
- **notifyPhoneEnteredBackground()** - tells watch phone is in background
- **stopAllMonitoring()** - allows watch app to go to background/sleep

#### 3. Watch Auto-Launch System (WatchHealthKitManager.swift)
- **startAutoLaunchSession()** - Creates background workout session for remote launching
- **Background session** - Keeps app process alive and launchable
- **Background refresh** - Enables automatic wake-up from phone commands

#### 4. Watch App Main (ImagineWatchApp.swift)
- Initializes auto-launch session on startup
- Uses `@Environment(\.scenePhase)` to detect app state changes
- Controls visibility with `WKExtension.isFrontmostTimeoutExtended`
- Schedules background refresh for persistent availability

#### 5. Watch Connectivity Manager (WatchConnectivityManager.swift)
- Receives commands from phone and posts local notifications
- Handles: `wakeUp`, `phoneEnteredForeground`, `phoneEnteredBackground`

## Lifecycle State Logic

```
shouldStayVisible = isPracticeActive || isPhoneInForeground

if shouldStayVisible:
    - Set WKExtension.isFrontmostTimeoutExtended = true
    - Schedule keep-alive notifications
    - Try to prevent backgrounding
else:
    - Set WKExtension.isFrontmostTimeoutExtended = false  
    - Cancel keep-alive notifications
    - Allow natural backgrounding
```

## Testing Instructions

### Step 1: Initial Setup
1. **Build and run iPhone app** - this will initialize connectivity and send wake command
2. **Build and run watch app** - this creates the auto-launch session
3. **Verify connection** - you should see heart rate readings start automatically

### Step 2: Test Automatic Launch
1. **Close iPhone app** (swipe up, swipe away)
2. **Close watch app** (press digital crown, swipe away)  
3. **Reopen iPhone app** 
4. **Watch app should automatically appear** - no manual interaction needed
5. **Check logs** - should see "Auto-launch session started"

### Step 3: Test Phone Background → Watch Background
1. **Ensure no practice is playing**
2. **iPhone app in foreground, watch app visible**
3. **Put iPhone app in background** (home button/swipe up)
4. **Wait 10-15 seconds** - watch app should go to background
5. **Check logs** - should see "Phone entered background" 

### Step 4: Test Practice Override
1. **Start a practice session** on iPhone
2. **Put iPhone app in background**
3. **Watch app should stay visible** and continue monitoring
4. **Check logs** - should see "Practice started - keeping watch app visible"

### Step 5: Test Practice End → Return to Normal
1. **End practice session**
2. **If iPhone still in background** - watch should go to background
3. **If iPhone comes to foreground** - watch should stay visible

## Debug Logs to Look For

### iPhone Logs
```
PhoneConnectivityManager: 🔔 Waking up watch app
PhoneConnectivityManager: 📱 Notifying watch: phone entered foreground
PhoneConnectivityManager: 📵 Notifying watch: phone entered background
AppDelegate: App entering background with no active practice - stopping watch monitoring
```

### Watch Logs  
```
🚀🚀🚀 WATCH APP STARTING UP 🚀🚀🚀
🔥🔥🔥 WATCH APP UI APPEARED 🔥🔥🔥
WatchHealthKitManager: 🚀 Starting auto-launch session
WatchConnectivityManager: 🔔 Wake up command received - auto-launching app
Watch: Background refresh scheduled - app can be auto-launched
Watch: Attempting to keep app visible
Watch: Auto-launch notification scheduled
```

## Current Capabilities

1. ✅ **Automatic Launch** - Watch app launches when phone app starts (after initial setup)
2. ✅ **Background Management** - Smart background/foreground transitions  
3. ✅ **Practice Override** - Stays active during meditation sessions
4. ✅ **Battery Optimization** - Efficient background sessions and monitoring

## Current Limitations

1. **WatchOS Restrictions** - System can still force backgrounding for battery/thermal reasons
2. **Notification Permissions** - User needs to allow notifications for keep-alive feature

## Battery Optimization

- **Background monitoring**: 5-minute intervals with low-power sensors
- **Intensive monitoring**: Real-time only during practice
- **Smart sleep**: Watch app sleeps when not needed
- **Efficient batching**: Heart rate data batched when appropriate

## Troubleshooting

### Watch App Not Responding
1. Force close and reopen watch app
2. Check iPhone connectivity in Settings > Watch
3. Restart both devices if needed

### No Heart Rate Data
1. Verify HealthKit permissions on watch
2. Ensure watch is worn snugly
3. Check for "Wrist Detection" in Watch settings

### Apps Not Syncing Lifecycle
1. Check WatchConnectivity logs for errors
2. Verify both apps are running initially  
3. Test with phone and watch on chargers (to avoid power management)

This implementation provides the most reliable watch app lifecycle management possible within WatchOS constraints while maintaining optimal battery efficiency. 