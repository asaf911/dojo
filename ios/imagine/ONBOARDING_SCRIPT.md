# Dojo Onboarding Script

## AI Onboarding Flow (7 Steps)

### Step 1: Welcome & Sensei Introduction
**Title:** "Welcome to Dojo [FirstName]," or "Welcome to Dojo Traveler,"

**Message:**
The world's first adaptive and measurable meditation system powered by AI.

I am Sensei, your personal guide throughout this journey.

Shall we begin?

**CTA:** "Yes"

---

### Step 2: Goal Understanding
**Preamble:** "Every journey begins with intention."

**Question:** "What would you like to work on right now?"

**Options (Multiple Selection):**
- Reduce stress
- Sleep better
- Improve focus
- Boost mood
- Spiritual growth
- Build consistency

**CTA Options:**
- Primary: "Continue"
- Skip: "Skip"

---

### Step 3: Baseline Understanding
**Preamble:** "Thanks."

**Question:** "How are you feeling today?"

**Options (Multiple Selection):**
- Stressed
- Tired or low
- Distracted
- Angry or tense
- Neutral
- Calm or energized

**CTA Options:**
- Primary: "Continue"
- Skip: "Skip"

---

### Step 4: Industry Insight
**Message:**
Everyone is different, and we all change from day to day.

Meditation isn't one-size-fits-all — it should change with you.

Does this feel true?

**CTA Options:**
- Primary: "Yes"
- Skip: "Not really"

---

### Step 5: Experience Tracking
**Preamble:** "Thank you for your honesty.

Let me understand your experience."

**Question:** "How have you practiced before?"

**Options (Multiple Selection):**
- Calm or Headspace
- Other apps
- YouTube or Spotify
- On my own
- Workshops and retreats
- I'm completely new

**CTA Options:**
- Primary: "Continue"
- Skip: "Skip"

---

### Step 6: Guidance Style
**Preamble:** "Thank you.

Dojo is different - it adapts to your goals, your state, and your progress."

**Question:** "How would you like the guidance to feel?"

**Options (Single Selection):**
- Calm & soft
- Direct & clear
- Scientific
- Spiritual

**CTA Options:**
- Primary: "Continue"
- Skip: "Skip"

---

### Step 7: Path Preparation
**Message:**
Thank you. I now have everything I need to build your personalized training path.

To continue, you'll need to unlock full access.

Would you like to proceed?

**CTA Options:**
- Primary: "Unlock"
- Skip: "Show all plans"

---

## Subscription Flow (4 Screens)

### Screen 1: Welcome Screen
**Title:** "Get full Dojo access"

**Key Points:**
1. **Sensei AI guidance**
   - AI-personalized meditations, tailored recommendations, and Q&A responses.

2. **Premium meditations**
   - Daily-life library: morning, evening, sleep + the Path course.

3. **Track progress with Health**
   - Apple Health, sensors, and stats to optimize your meditation path.

4. **Cancel anytime**
   - Keep access for the time you stay covered

**CTA:** "Try it all $0"

---

### Screen 2: Trial Reminder Screen
**Message:**
We'll notify you

**2 days** before your

**7-day free trial** ends

**CTA:** "Start free 7-day trial"
*(Requests notification permissions)*

---

### Screen 3: Pricing Overview Screen
**Main Text:**
**7-day free trial**

Then $39.99/year after trial

That's only $3.33 per month!

**Social Proof:** SubscriptionSocialHeader component

**CTA Section:**
- Text: "No commitment. Cancel anytime."
- Primary Button: "Start your 7-day trial"
- Secondary Link: "View all plans" (opens All Plans sheet)

**Close Button:** X button in top-right corner

---

### Screen 4: All Plans Screen
**Title:** "Choose Your Perfect Plan"

**Content:**
- Displays all available subscription packages from RevenueCat
- Shows plan details including:
  - Plan title
  - Localized price string
  - Description
  - Discount percentage (if annual - 67% discount)

**Social Proof:** SubscriptionSocialHeader component

**CTA Section:**
- Text (if trial available): "No commitment. Cancel anytime."
- Primary Button: 
  - "Start free 7-day trial" (if introductory discount available)
  - "Continue" (if no trial)
- Footer Links: "Terms of Use" | "Privacy Policy"

**Close Button:** X button in top-right corner

---

## Flow Completion

After subscription purchase (or user closes the flow), the app:
- Logs analytics event: `subscription_flow_exited`
- Posts `SubscriptionFlowCompleted` notification
- Navigates user back to main view

