# Apple Watch Wake-Up Signal Improvements

## Problem Statement

Users were experiencing poor Apple Watch connectivity when starting meditation sessions:
- "Starting heart rate monitoring on your Apple Watch" message appeared
- But then immediately showed "Heart rate monitoring unavailable. Check your Apple Watch"
- Even when turning on the watch manually, status didn't change for 30+ seconds
- Poor user experience with unreliable heart rate monitoring

## Root Cause Analysis

From the logs, we identified several issues:
1. **Watch App Not Ready**: The watch app wasn't actively running when meditation commands were sent
2. **Missing Wake-Up Protocol**: No mechanism to "wake up" the watch app before sending commands
3. **Improper Message Handling**: `watchAppDidBecomeActive` message wasn't being handled correctly
4. **No Automatic Retry**: When the watch became available, the system didn't automatically retry failed sessions

## Comprehensive Solution Implemented

### 1. iPhone Side Improvements (`PhoneConnectivityManager.swift`)

#### A. Automatic Wake-Up Signal on App Launch
```swift
private func setupWatchConnectivity() {
    // ... existing setup ...
    
    // Send wake-up signal after brief delay to let session activate
    DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
        self.sendWakeUpSignal()
    }
}
```

#### B. Smart Wake-Up Command Implementation
```swift
private func sendWakeUpSignal() {
    let wakeUpCommand: [String: Any] = [
        "command": "wakeUp",
        "timestamp": Date().timeIntervalSince1970,
        "sessionId": UUID().uuidString
    ]
    
    // Try immediate message first, fall back to background transfer
    if session.isReachable {
        session.sendMessage(wakeUpCommand, replyHandler: { response in
            self.isWatchReady = true
        })
    } else {
        sendWakeUpViaBackgroundTransfer(wakeUpCommand)
    }
}
```

#### C. Watch Readiness Tracking
- Added `isWatchReady` property to track when watch is ready for commands
- Modified `startAutomaticMeditationSession()` to check readiness before sending commands
- Automatic wake-up signal if watch isn't ready

#### D. Improved Message Handling
```swift
case "watchAppDidBecomeActive":
    self.isWatchReady = true
    // If we have a pending meditation session, restart the command
    if self.isMeditationSessionActive && self.heartRateStatus == .error {
        self.heartRateStatus = .preparing
        self.sendAutomaticStartCommand()
        self.startHeartRateTimeout()
    }

case "watchReady":
    self.isWatchReady = true
    // If we have an errored meditation session, retry it
    if self.isMeditationSessionActive && self.heartRateStatus == .error {
        self.heartRateStatus = .preparing
        self.sendAutomaticStartCommand()
        self.startHeartRateTimeout()
    }
```

#### E. Manual Retry Method
```swift
func retryHeartRateMonitoring() {
    // Send wake-up signal to ensure watch is ready
    sendWakeUpSignal()
    
    // Send start command after brief delay
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        self.sendAutomaticStartCommand()
        self.startHeartRateTimeout()
    }
}
```

### 2. Watch Side Improvements (`WatchConnectivityManager.swift`)

#### A. Wake-Up Command Handling
```swift
case "wakeUp":
    print("WatchConnectivityManager: 🌅 Received wake-up signal from iPhone")
    self.sendWakeUpResponse()
```

#### B. Wake-Up Response Method
```swift
func sendWakeUpResponse() {
    let message = [
        "type": "watchReady",
        "timestamp": Date().timeIntervalSince1970
    ] as [String : Any]
    
    if session.isReachable {
        session.sendMessage(message, replyHandler: nil)
    } else {
        session.transferUserInfo(message)
    }
}
```

#### C. Enhanced App Active Notifications
- Improved `notifyWatchAppDidBecomeActive()` to use background transfer when not reachable
- Added automatic wake-up response when app becomes active

### 3. Watch App Lifecycle Improvements (`ImagineWatchApp.swift`)

#### A. Proactive Wake-Up Signals
```swift
case .active:
    WatchConnectivityManager.shared.notifyWatchAppDidBecomeActive()
    // Also send wake-up response to let iPhone know we're ready
    WatchConnectivityManager.shared.sendWakeUpResponse()
```

## Expected User Experience Improvements

### Before:
1. User taps meditation practice
2. "Starting heart rate monitoring on your Apple Watch"
3. "Heart rate monitoring unavailable. Check your Apple Watch"
4. User manually opens watch app
5. Wait 30+ seconds with no change
6. Frustration and abandonment

### After:
1. **App Launch**: iPhone automatically sends wake-up signal to watch
2. **User taps practice**: Watch is already ready and responds immediately
3. **If watch is sleeping**: Automatic wake-up signal sent before meditation command
4. **If error occurs**: User opening watch app automatically retries the session
5. **Background transfers**: Guaranteed delivery even when watch not immediately reachable

## Technical Benefits

1. **Proactive Communication**: Wake-up signals ensure watch is ready before commands
2. **Automatic Recovery**: Failed sessions automatically retry when watch becomes available
3. **Reliable Delivery**: Both immediate messages and background transfers for guaranteed delivery
4. **Better Status Tracking**: Clear indication of watch readiness state
5. **User-Friendly Messages**: More descriptive status messages guide user actions

## Testing Scenarios

### Scenario 1: Watch App Closed
1. iPhone app launches → Wake-up signal sent via background transfer
2. User selects meditation → Additional wake-up if needed
3. User opens watch app → Automatic session retry
4. Heart rate monitoring starts immediately

### Scenario 2: Watch App Open
1. iPhone app launches → Wake-up signal received immediately
2. User selects meditation → Instant heart rate monitoring start
3. Seamless experience with no delays

### Scenario 3: Watch Not Reachable
1. Commands sent via background transfer (guaranteed delivery)
2. When watch becomes reachable → Automatic session retry
3. No lost commands or failed sessions

## Implementation Status

✅ **Complete**: All wake-up signal functionality implemented
✅ **Complete**: Enhanced message handling and automatic retry
✅ **Complete**: Improved user feedback and status messages
✅ **Complete**: Comprehensive error recovery
✅ **Ready for Testing**: Full system ready for user validation

This implementation follows Apple Watch best practices and ensures reliable communication regardless of watch app state or connectivity conditions. 