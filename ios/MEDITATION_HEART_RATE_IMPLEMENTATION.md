# 🧘 Real-Time Heart Rate Streaming for Meditation Sessions

## 🎯 Implementation Overview

This implementation provides real-time heart rate monitoring during meditation sessions using Apple Watch's `HKWorkoutSession` with proper background execution and clean session management.

## 🏗 Architecture

### iPhone Side (`PhoneConnectivityManager`)
- **New Command Structure**: `startWorkout` and `stopWorkout` commands
- **Session Management**: Tracks meditation session state with `isMeditationSessionActive`
- **Background Continuation**: Maintains heart rate streaming when iPhone is backgrounded
- **Legacy Compatibility**: Maintains backward compatibility with existing methods

### Watch Side (`WatchHealthKitManager`)
- **Meditation Workout Session**: Uses `HKWorkoutSession` with `.mindAndBody` activity type
- **Real-time Streaming**: `HKLiveWorkoutBuilder` for continuous heart rate data
- **Safety Timeout**: Auto-terminates sessions after 30 minutes
- **Clean Termination**: Ends sessions without saving to HealthKit

## 🔄 Session Flow

### 1. Starting Meditation Session

**iPhone:**
```swift
PhoneConnectivityManager.shared.startMeditationSession()
```

**Watch:**
```swift
WatchHealthKitManager.shared.startMeditationWorkout()
```

**Configuration:**
- Activity Type: `.mindAndBody` (perfect for meditation)
- Location Type: `.unknown` (location not relevant)
- Data Source: `HKLiveWorkoutDataSource` for real-time heart rate

### 2. Heart Rate Streaming

**Data Flow:**
1. Watch collects heart rate via `HKLiveWorkoutBuilder`
2. Processes data in `workoutBuilder(_:didCollectDataOf:)`
3. Sends to iPhone via `WCSession` with message type `"heartRateData"`
4. iPhone updates UI via `PracticeBPMTracker`

**Message Format:**
```swift
[
    "type": "heartRateData",
    "timestamp": Date().timeIntervalSince1970,
    "bpm": Double,
    "sessionType": "meditation",
    "isMeditationSession": true
]
```

### 3. Session Summary

**End of Session:**
- Watch calculates start/end/average BPM
- Sends summary via `"meditationHeartRateSummary"` message
- iPhone displays results in post-practice UI

### 4. Clean Termination

**Watch:**
- Calls `workoutSession.end()` to stop session
- **Does NOT call** `workoutBuilder.finishWorkout()` to avoid saving
- Clears session data and resets state

## 🛡 Safety Features

### Auto-Timeout (30 minutes)
```swift
private let safetyTimeoutDuration: TimeInterval = 30 * 60 // 30 minutes
```

**Behavior:**
- Automatically terminates meditation sessions after 30 minutes
- Sends timeout notification to iPhone
- Prevents indefinite background execution

### Background Execution
- Uses `HKWorkoutSession` for proper background heart rate access
- Continues monitoring when watch screen is off
- Maintains session across app state changes

## 🔌 Integration Points

### Timer Sessions
```swift
// TimerManager.swift
func start() {
    // ... existing code ...
    PhoneConnectivityManager.shared.startMeditationSession()
}

func endSession() {
    PhoneConnectivityManager.shared.stopMeditationSession()
    // ... existing code ...
}
```

### Audio Practice Sessions
```swift
// AudioPlayerManager.swift
func play() {
    // ... existing code ...
    PhoneConnectivityManager.shared.startMeditationSession()
}

func stopAudio() {
    PhoneConnectivityManager.shared.stopMeditationSession()
    // ... existing code ...
}
```

## 📱 Command Structure

### New Commands
- `startWorkout`: Initiates meditation workout session
- `stopWorkout`: Cleanly terminates meditation workout session

### Legacy Support
- `startIntensiveMonitoring` → redirects to `startWorkout`
- `forceIntensiveMonitoring` → redirects to `startWorkout`
- `resumeBackgroundMonitoring` → stops meditation, starts background

## 🔄 Session Types

### Background Monitoring
- **Frequency**: Every 30 seconds
- **Method**: Periodic `HKSampleQuery`
- **Use Case**: When app is open but no meditation active

### Meditation Workout
- **Frequency**: Real-time (every few seconds)
- **Method**: `HKLiveWorkoutBuilder` with workout session
- **Use Case**: During active meditation sessions

## 🎛 Configuration

### HealthKit Permissions
```swift
// Read-only permissions (no write needed)
let readTypes: Set<HKObjectType> = [heartRateType, workoutType]
healthStore.requestAuthorization(toShare: nil, read: readTypes)
```

### Workout Configuration
```swift
let configuration = HKWorkoutConfiguration()
configuration.activityType = .mindAndBody  // Perfect for meditation
configuration.locationType = .unknown      // Location not relevant
```

## 🚨 Error Handling

### Fallback Mechanisms
- If workout session fails → falls back to periodic queries
- If WCSession not reachable → uses `transferUserInfo` for reliability
- If HealthKit denied → graceful degradation without heart rate

### Timeout Handling
- 30-minute safety timeout prevents runaway sessions
- Automatic cleanup on app termination
- Session state recovery on reconnection

## 📊 Data Flow

```
iPhone App (Meditation Start)
    ↓ WCSession
Watch App (Workout Session)
    ↓ HKLiveWorkoutBuilder
Apple Watch (Heart Rate Sensor)
    ↓ Real-time BPM
Watch App (Process & Send)
    ↓ WCSession
iPhone App (UI Update)
```

## 🔧 Debugging

### Console Logs
- **iPhone**: `PhoneConnectivityManager: 🧘 Starting meditation session`
- **Watch**: `WatchHealthKitManager: ✅ Meditation workout is now running`
- **Heart Rate**: `WatchHealthKitManager: 💓 Heart rate: 75 BPM (meditation)`

### Key Indicators
- ✅ Workout session state: `running`
- ✅ Heart rate data flowing every 5-10 seconds
- ✅ Session summary sent at end
- ✅ Clean termination without HealthKit save

## 🎯 Benefits

1. **Real-time Monitoring**: Continuous heart rate during meditation
2. **Background Execution**: Works when iPhone is locked/backgrounded
3. **Clean Sessions**: No clutter in user's workout history
4. **Safety First**: Auto-timeout prevents runaway sessions
5. **Reliable Communication**: Dual delivery methods for maximum reliability
6. **Legacy Compatible**: Existing code continues to work

## 🚀 Usage Examples

### Starting a Timer Session
```swift
let timerManager = TimerManager(totalSeconds: 600) // 10 minutes
timerManager.start() // Automatically starts heart rate monitoring
```

### Starting an Audio Practice
```swift
audioPlayerManager.playAudioFile(file: meditationFile, durationIndex: 0)
// Heart rate monitoring starts when play() is called
```

### Manual Control
```swift
// Start meditation session
PhoneConnectivityManager.shared.startMeditationSession()

// Stop meditation session  
PhoneConnectivityManager.shared.stopMeditationSession()
```

This implementation provides a robust, safe, and user-friendly heart rate monitoring system specifically designed for meditation use cases. 