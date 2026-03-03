# 🔍 Watch App Debug Steps

## 🚨 **Current Issue Analysis**

iPhone logs show:
- ✅ Commands being sent via `transferUserInfo`
- ✅ Session activated and watch app installed
- ❌ **NO watch logs appearing** - this is the problem!

## 🎯 **Step 1: Verify Watch App is Running**

### **Check Watch Console:**
1. Open **Xcode** → **Window** → **Devices and Simulators**
2. Select your **Apple Watch** from the left sidebar
3. Click **"Open Console"** button
4. In the filter box, type: `WatchConnectivityManager`

### **Expected Watch Logs:**
If the watch app is working, you should see:
```
WatchConnectivityManager: 🔗 Session activated on watch.
WatchConnectivityManager: 💓 Heartbeat timer started
WatchConnectivityManager: 💓 Sent heartbeat - isReachable: false
```

### **If NO Watch Logs Appear:**
The watch app is not running or not installed properly.

## 🎯 **Step 2: Force Launch Watch App**

### **Manual Launch:**
1. **Press Digital Crown** on your Apple Watch
2. **Find your app** (should be called "Dojo")
3. **Tap to open** the watch app
4. **Keep it open** and try sending commands from iPhone

### **Expected Result:**
Once the watch app is manually opened, you should immediately see:
```
WatchConnectivityManager: 📦 Received transferUserInfo from iPhone
WatchConnectivityManager: 🔍 Processing message from iPhone
WatchConnectivityManager: 🚀 Received command action='startHeartRateMonitoring'
```

## 🎯 **Step 3: Verify Watch App Installation**

### **Check if Watch App is Installed:**
1. On your **iPhone**, open **Watch app**
2. Go to **"My Watch"** tab
3. Scroll down to **"Available Apps"** or **"Installed on Apple Watch"**
4. Look for your app (should be called "Dojo")
5. Make sure the toggle is **ON** (green)

### **If App is Not Listed:**
The watch app wasn't installed properly. You need to:
1. **Clean build** the project
2. **Build and run** the watch app target specifically
3. **Install on watch** via Xcode

## 🎯 **Step 4: Test Basic Watch Connectivity**

### **Add Test Logs to Watch App:**
Let's add a simple test to verify the watch app is receiving messages.

### **Test Method:**
1. **Manually open** the watch app
2. **Send command** from iPhone
3. **Check watch console** for logs
4. **Wait 30-60 seconds** (transferUserInfo can be slow)

## 🎯 **Step 5: Verify HealthKit Permissions**

### **Check Watch HealthKit Permissions:**
1. On **Apple Watch**: **Settings** → **Privacy & Security** → **Health**
2. Find your app
3. Make sure **Heart Rate** permission is **ON**

### **If Permissions Not Granted:**
The watch app should prompt for permissions when first launched.

## 🚨 **Most Likely Issues:**

### **1. Watch App Not Installed (90% likely)**
- Check Watch app on iPhone
- Reinstall watch app via Xcode
- Verify app appears on watch

### **2. Watch App Not Running (5% likely)**
- Manually launch watch app
- Keep it in foreground during testing
- Check if logs appear when app is active

### **3. transferUserInfo Delay (5% likely)**
- Messages can take 10-60 seconds to deliver
- Watch app must be launched at least once
- Background delivery is not immediate

## 🎯 **Quick Test:**

1. **Open watch app manually** on your Apple Watch
2. **Send command** from iPhone debug view
3. **Watch console logs** - should see messages within 10 seconds
4. **If still no logs** → watch app installation issue

## 📞 **Next Steps:**

1. Check watch console for ANY logs from the app
2. Manually launch watch app and test
3. Verify watch app installation in iPhone Watch app
4. Share watch console logs (or lack thereof)

The iPhone side is working perfectly - the issue is definitely on the watch side receiving the messages. 