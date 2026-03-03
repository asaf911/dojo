# Apple Watch Debug Guide - Communication Issues

## 🔍 **Problem Analysis (Based on Your Logs)**

Your logs show the automatic system is working correctly on iPhone, but the Watch app isn't responding:

### ✅ **iPhone Side (Working)**
- WatchConnectivity activated
- Apple Watch paired detected  
- Automatic session triggered on preload
- Command sent: `startAutomaticMeditation`

### ❌ **Watch Side (Not Responding)**
- No response to `startAutomaticMeditation` command
- Timeout after 15 seconds
- Unknown message type: `watchAppDidBecomeActive`

## 🛠️ **Immediate Debug Steps**

### 1. **Check Watch App Console Logs**
Open **Console.app** on your Mac:
1. Connect your Apple Watch to your iPhone
2. Open Console.app → Devices → Your Apple Watch
3. Filter for: `ImagineWatch` or `WatchConnectivityManager`
4. Launch your Watch app manually
5. Check for error messages

**Expected logs on Watch:**
```
WatchConnectivityManager: 🔗 Watch session activated
WatchConnectivityManager: 🧘 Starting automatic meditation session
WatchHealthKitManager: 🎯 Starting meditation workout
```

### 2. **Watch App Permissions Check**
Ensure your Watch app has HealthKit permissions:
1. Open **Settings** on Apple Watch
2. Go to **Privacy & Security** → **Health**  
3. Find your app and ensure **Heart Rate** is enabled

### 3. **Force Restart Watch Connectivity**
1. **Restart Apple Watch**: Hold side button + Digital Crown
2. **Restart iPhone app**: Force quit and reopen
3. **Re-pair if necessary**: Settings → Apple Watch → Unpair → Re-pair

## 🔧 **Code-Level Debug**

### Problem 1: Missing Message Handler
The log shows `❓ Unknown message type: watchAppDidBecomeActive` - this means the iPhone doesn't recognize messages from the Watch.

**Solution Applied**: Updated `PhoneConnectivityManager.swift` to handle this message type.

### Problem 2: Watch App Not Responding to Commands
The Watch receives `startAutomaticMeditation` but doesn't confirm receipt.

**Check**: Ensure Watch app has these key components:
- `WatchConnectivityManager` delegate methods
- `WatchHealthKitManager` workout session
- Proper message sending back to iPhone

## 📋 **Step-by-Step Test Protocol**

### Test 1: Basic Connectivity
1. Open iPhone app
2. Check: `PhoneConnectivityManager: ✅ Session activated - Connected: true`
3. Open Watch app manually  
4. Check iPhone logs for: Watch app activation message

### Test 2: Manual Heart Rate Test
1. Open **Heart Rate app** on Apple Watch
2. Start a measurement
3. Verify heart rate appears in iPhone **Health app**
4. This confirms basic HealthKit permissions

### Test 3: Automatic Session Test
1. Open iPhone app
2. Select any meditation (Perfect Breath)  
3. **Don't press play yet** - just select it
4. Check logs for: `📤 Command sent: startAutomaticMeditation`
5. Watch for timeout or success message

## 🚨 **Most Likely Issues & Solutions**

### Issue 1: Watch App Not Receiving Messages
**Cause**: WatchConnectivity session not properly activated on Watch
**Solution**: Restart both iPhone and Watch apps

### Issue 2: HealthKit Permissions Denied
**Cause**: Watch app lacks heart rate permission  
**Solution**: Grant permissions in Watch Settings → Privacy & Security → Health

### Issue 3: Watch App Crashing Silently
**Cause**: Code error in `WatchHealthKitManager.startMeditationWorkout()`
**Solution**: Check Console.app for crash logs

### Issue 4: Message Format Mismatch
**Cause**: iPhone and Watch using different message formats
**Solution**: Already fixed in the refactored code

## 📝 **Next Steps for You**

1. **Check Watch Console logs** (most important)
2. **Verify HealthKit permissions** on Watch
3. **Test with Heart Rate app** to confirm basic functionality
4. **Report back with Watch console logs** if issue persists

## 📞 **If Still Not Working**

Provide these logs:
- **Watch Console logs** (from Console.app)
- **HealthKit permission status** (Watch Settings)
- **Heart Rate app test results** (does it work independently?)

The automatic system is working perfectly on iPhone - we just need to fix the Watch side communication! 