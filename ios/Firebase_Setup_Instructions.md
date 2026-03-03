# 🔥 Firebase Setup Instructions - Smart Body Scan Module

## 📁 Firebase Folder Structure

Create this folder structure in your Firebase Storage:

```
gs://imagine-c6162.appspot.com/
├── Timer/
│   └── Cues/
│       └── TimerCues.json (replace existing)
└── modules/           ← NEW FOLDER
    └── body_scan/     ← NEW FOLDER
        ├── body_scan_2min_v1.mp3
        ├── body_scan_5min_v1.mp3
        └── body_scan_10min_v1.mp3
```

## 📋 Step-by-Step Instructions

### Step 1: Create the Modules Folder Structure

1. **Go to Firebase Console** → Storage
2. **Navigate to**: `gs://imagine-c6162.appspot.com/`
3. **Create folder**: `modules`
4. **Inside modules, create folder**: `body_scan`

### Step 2: Upload Updated TimerCues.json

1. **Replace** the existing `Timer/Cues/TimerCues.json` with the new version:
   - **Location**: `/Users/asafshamir/Documents/imagine/TimerCues_updated.json`
   - **Destination**: `gs://imagine-c6162.appspot.com/Timer/Cues/TimerCues.json`

### Step 2.5: Upload Updated AI Rules 🧠

1. **Replace** the existing AI rules file with the new smart body scan version:
   - **Location**: `/Users/asafshamir/Documents/imagine/ai_meditation_rules_simple_firebase.json`
   - **Destination**: Your current AI rules location in Firebase (e.g., `ai_meditation_rules_simple.json`)
   - **Important**: This contains the smart body scan logic that prevents overlaps!

### Step 3: Upload Body Scan Audio Files

Create and upload these 3 audio files to `gs://imagine-c6162.appspot.com/modules/body_scan/`:

#### Required Files:
1. **`body_scan_2min_v1.mp3`** (2-minute body scan)
   - For short sessions (5-8 minutes)
   - Quick, focused body awareness
   
2. **`body_scan_5min_v1.mp3`** (5-minute body scan)
   - For medium sessions (9-20 minutes)
   - Standard comprehensive body scan
   
3. **`body_scan_10min_v1.mp3`** (10-minute body scan)
   - For long sessions (21+ minutes)
   - Deep, detailed body awareness practice

## 🎯 What Happens After Upload

### Automatic Smart Selection:
- **AI prompt**: "Create a 7-minute stress relief session"
  - **AI chooses**: `BS2` (2-minute body scan)
  
- **AI prompt**: "I need a 15-minute relaxation meditation"
  - **AI chooses**: `BS5` (5-minute body scan)
  
- **AI prompt**: "Give me a 25-minute deep meditation"
  - **AI chooses**: `BS10` (10-minute body scan)

### Backward Compatibility:
- Existing `BS` cue still works normally
- No changes needed to existing meditations
- Users won't notice any difference except better body scans

## 🧪 Testing Instructions

### Test Prompts:
1. **"Create a quick 5-minute meditation"** → Should use BS2
2. **"I want a 12-minute relaxation session"** → Should use BS5  
3. **"Give me a long 30-minute meditation"** → Should use BS10

### Expected Results:
- Look for log messages: `🧘 SMART_BODY_SCAN: Enhanced BS -> BS5 for 12min session`
- Body scan will be appropriately paced for session length
- Users get better meditation experience automatically

## 📊 Future Expansion

This structure supports easy addition of new modules:

```
modules/
├── body_scan/          ← DONE ✅
├── breathwork/         ← FUTURE
├── mantra/            ← FUTURE
└── visualization/     ← FUTURE
```

Each new module will follow the same pattern with duration variants and smart AI selection.

---

**🎉 Ready to Deploy!** Once you upload the files, the smart body scan selection will work immediately!