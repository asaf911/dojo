# Apple Watch Integration - Troubleshooting Guide

## 🔍 Issues Identified from Logs

Based on your logs from 11:54, here are the key issues and fixes:

### ✅ What's Working
- **WatchConnectivity is active**: `PhoneConnectivityManager: ✅ Session activated - Connected: true`
- **Watch pairing detected**: `WatchPairingManager: Apple Watch paired: true`
- **Automatic system triggers**: `PhoneConnectivityManager: 🧘 Starting automatic meditation session`
- **Commands sent to watch**: `PhoneConnectivityManager: 📤 Command sent: startAutomaticMeditation`

### ❌ Issues Found
1. **Heart rate monitoring timeout**: `PhoneConnectivityManager: ⏰ Heart rate monitoring timeout`
2. **Unknown message types**: `❓ Unknown message type: meditationSessionTimeout` and `watchAppDidBecomeActive`
3. **Watch not confirming session start**: No confirmation received from Watch side

## 🔧 Fixes Applied

### 1. **iPhone Side (PhoneConnectivityManager.swift)**
- ✅ Added handling for `meditationSessionTimeout` messages
- ✅ Added handling for `watchAppDidBecomeActive` messages  
- ✅ Improved timeout handling with proper cleanup
- ✅ Added session restart capability when watch app becomes active

### 2. **Watch Side (WatchConnectivityManager.swift)**
- ✅ Refactored message handling to use proper command structure
- ✅ Added dedicated methods for sending specific message types
- ✅ Improved error handling and logging
- ✅ Added automatic session start confirmation

### 3. **Watch HealthKit (WatchHealthKitManager.swift)**
- ✅ Integrated with connectivity manager for proper notifications
- ✅ Added automatic session start confirmation to iPhone
- ✅ Improved timeout handling with proper iPhone notification
- ✅ Added session stop confirmation

### 4. **Watch App Lifecycle (ImagineWatchApp.swift)**
- ✅ Added proper notification when watch app becomes active
- ✅ Automatic restart capability for interrupted sessions

## 🧪 Testing Steps

1. **Build and Deploy**:
   ```bash
   # Build for iOS
   xcodebuild -project imagine.xcodeproj -scheme imagine -destination 'platform=iOS Simulator,name=iPhone 15 Pro' build
   
   # Build for watchOS 
   xcodebuild -project imagine.xcodeproj -scheme "ImagineWatch Watch App" -destination 'platform=watchOS Simulator,name=Apple Watch Series 9 (45mm)' build
   ```

2. **Test Flow**:
   - Open iPhone app
   - Select a meditation (should see: `📤 Command sent: startAutomaticMeditation`)
   - Check Watch app opens automatically
   - Verify heart rate data flows: `💓 Heart rate updated: XXX`
   - Test timeout handling (wait 2 minutes for automatic stop)

3. **Watch App Manual Test**:
   - Open Watch app manually
   - Should see: `👀 Watch app became active`
   - If iPhone has active session, should restart automatically

## 🔮 Expected Log Flow (After Fixes)

**iPhone logs should show:**
```
PhoneConnectivityManager: 🧘 Starting automatic meditation session
PhoneConnectivityManager: 📤 Command sent: startAutomaticMeditation
PhoneConnectivityManager: 🟢 Watch confirmed meditation session started
PhoneConnectivityManager: 💓 Heart rate updated: 75
PhoneConnectivityManager: 💓 Heart rate updated: 78
PhoneConnectivityManager: 🛑 Watch confirmed meditation session stopped
```

**Watch logs should show:**
```
WatchConnectivityManager: 📨 Received command: startAutomaticMeditation
WatchConnectivityManager: 🧘 Starting automatic meditation session
WatchHealthKitManager: ✅ Meditation workout session started successfully
WatchHealthKitManager: 💓 Heart rate: 75 BPM
WatchHealthKitManager: 💓 Heart rate: 78 BPM
WatchHealthKitManager: 🛑 Stopping automatic meditation workout
```

## 🚨 Common Issues & Solutions

### Issue: "Heart rate monitoring timeout"
**Cause**: Watch app not running or not receiving commands
**Solution**: 
1. Ensure Watch app is installed and running
2. Check WatchConnectivity permissions
3. Manually open Watch app, then try again

### Issue: "Unknown message type"
**Cause**: Outdated message handling (fixed in refactoring)
**Solution**: Deploy updated code to both iPhone and Watch

### Issue: No heart rate data received
**Cause**: HealthKit permissions or workout session not started
**Solution**:
1. Check HealthKit permissions on Watch
2. Ensure workout session starts properly
3. Check logs for `✅ Meditation workout session started successfully`

### Issue: Session doesn't stop automatically
**Cause**: Timeout timer not working or cleanup issues
**Solution**:
1. Check safety timeout is set (45 minutes max)
2. Verify stop commands are received properly
3. Manual stop via audio stop should trigger cleanup

## 🔄 Testing Protocol

1. **Fresh Start**: Kill both apps, restart iPhone app first
2. **Monitor Logs**: Use Console.app to watch real-time logs
3. **Test Scenarios**:
   - Normal flow (preload → play → stop)
   - Watch app manual open during session
   - Timeout scenarios (leave running for 2+ minutes)
   - Background/foreground transitions

## 📱 Quick Debug Commands

```bash
# Watch logs in real-time
xcrun simctl spawn booted log stream --predicate 'process CONTAINS "imagine"'

# Check WatchConnectivity status
xcrun simctl spawn booted log stream --predicate 'subsystem CONTAINS "WatchConnectivity"'
```

The refactored system should now work reliably with proper automatic heart rate monitoring! 