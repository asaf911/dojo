# OneSignal Path Journey Setup Guide

This guide explains how to set up automated OneSignal Journeys using the implemented path tagging strategy to drive user engagement and completion.

## Overview

The iOS app now automatically tags users with comprehensive path progress data that enables sophisticated automated messaging campaigns in OneSignal Journeys.

## Available Tags

### Core Progress Tags
- `path_status`: "not_started" | "in_progress" | "completed"
- `path_total_steps`: Total number of steps in the path
- `path_completed_steps`: Number of completed steps
- `path_completion_percent`: Completion percentage (0-100)

### Activity Tracking Tags
- `path_last_activity`: Unix timestamp of last path activity
- `path_days_inactive`: Days since last path activity
- `path_streak_days`: Current consecutive days streak
- `path_longest_streak`: Longest streak achieved

### Next Step Tags (when in progress)
- `path_next_step_id`: ID of the next step to complete
- `path_next_step_order`: Order number of next step
- `path_next_step_type`: "lesson" | "practice"
- `path_next_step_title`: Human-readable title

### Last Completed Tags (when progress exists)
- `path_last_completed_step`: ID of last completed step
- `path_last_completed_order`: Order number of last completed step
- `path_last_completed_type`: "lesson" | "practice"

## Journey Configurations

### 1. New User Onboarding Journey

**Purpose**: Encourage users who haven't started the path

**Entry Rules**:
- Include Segment: `path_status = "not_started"`
- Future additions only: ✅ (prevent re-entry)

**Journey Flow**:
```
Entry → Wait (1 day) → Push Notification → Wait (2 days) → Yes/No Branch
                                                            ├─ Yes: Exit
                                                            └─ No: Email Follow-up
```

**Push Notification Message**:
- Title: "Ready to begin your mindfulness journey?"
- Body: "Start with your first path step and discover inner peace."
- Deep Link: `imagine://path`

### 2. Step Re-engagement Journey

**Purpose**: Re-engage users who have stalled on their path

**Entry Rules**:
- Include Segment: `path_status = "in_progress" AND path_days_inactive >= 2`
- Re-entry: Every time (allow re-engagement for each stall)

**Journey Flow**:
```
Entry → Push Notification → Wait (3 days) → Yes/No Branch → SMS Follow-up
                                             ├─ Clicked: Exit
                                             └─ Not Clicked: Continue
```

**Push Notification Message**:
- Title: "Your mindfulness journey awaits"
- Body: "Continue with {{ path_next_step_type }} {{ path_next_step_order }}: {{ path_next_step_title }}"
- Deep Link: `imagine://path/step/{{ path_next_step_id }}`

### 3. Milestone Celebration Journey

**Purpose**: Celebrate user progress at key milestones

**Entry Rules**:
- Include Segment: `path_completion_percent = 25` (create separate journeys for 25, 50, 75)
- Future additions only: ✅

**Journey Flow**:
```
Entry → Push Notification → Wait (1 hour) → In-App Message
```

**Push Notification Message**:
- Title: "Amazing progress! 🎉"
- Body: "You're {{ path_completion_percent }}% through your mindfulness path!"
- Deep Link: `imagine://path`

### 4. Path Completion Journey

**Purpose**: Celebrate path completion and encourage continued practice

**Entry Rules**:
- Include Segment: `path_status = "completed"`
- Future additions only: ✅

**Journey Flow**:
```
Entry → Wait (1 hour) → Push Notification → Wait (24 hours) → Email Celebration
```

**Push Notification Message**:
- Title: "Congratulations! Path Complete! 🏆"
- Body: "You've mastered your mindfulness journey. Continue practicing to maintain your growth."

### 5. Streak Recovery Journey

**Purpose**: Re-engage users who had a streak but became inactive

**Entry Rules**:
- Include Segment: `path_longest_streak >= 3 AND path_days_inactive >= 3 AND path_status = "in_progress"`
- Re-entry: Every 7 days

**Journey Flow**:
```
Entry → Wait (until 6 PM) → Push Notification → Wait (2 days) → Email Follow-up
```

**Push Notification Message**:
- Title: "Your {{ path_longest_streak }}-day streak is waiting"
- Body: "Don't let your momentum fade. Continue your mindfulness practice tonight."

## Segment Creation Guide

### 1. Not Started Segment
- **Filter**: `path_status = "not_started"`
- **Use**: Onboarding Journey

### 2. Stalled Users Segment
- **Filter**: `path_status = "in_progress" AND path_days_inactive >= 2`
- **Use**: Re-engagement Journey

### 3. 25% Milestone Segment
- **Filter**: `path_completion_percent = 25`
- **Use**: 25% Celebration Journey

### 4. 50% Milestone Segment
- **Filter**: `path_completion_percent = 50`
- **Use**: 50% Celebration Journey

### 5. 75% Milestone Segment
- **Filter**: `path_completion_percent = 75`
- **Use**: 75% Celebration Journey

### 6. Completed Path Segment
- **Filter**: `path_status = "completed"`
- **Use**: Completion Celebration Journey

### 7. Streak Recovery Segment
- **Filter**: `path_longest_streak >= 3 AND path_days_inactive >= 3 AND path_status = "in_progress"`
- **Use**: Streak Recovery Journey

## Time Window Recommendations

### Optimal Send Times
- **Morning Motivation**: 8 AM - 10 AM (for starting new steps)
- **Evening Wind-down**: 6 PM - 8 PM (for mindfulness practices)
- **Weekend Encouragement**: Saturday 10 AM (for re-engagement)

### Time Window Settings
For evening mindfulness content:
- Days: Monday-Sunday
- Hours: 18:00-20:00 (6 PM - 8 PM)
- Timezone: User's local timezone

## Message Personalization

### Available Variables
- `{{ path_next_step_type }}`: lesson/practice
- `{{ path_next_step_order }}`: 1, 2, 3...
- `{{ path_next_step_title }}`: Human-readable step name
- `{{ path_completion_percent }}`: 25, 50, 75, etc.
- `{{ path_completed_steps }}`: Number completed
- `{{ path_total_steps }}`: Total steps
- `{{ path_longest_streak }}`: Best streak achieved

### Example Personalized Messages
```
"Ready for {{ path_next_step_type }} {{ path_next_step_order }}?"
"You're {{ path_completed_steps }}/{{ path_total_steps }} through your journey!"
"Your {{ path_longest_streak }}-day streak shows real commitment."
```

## Deep Link Configuration

### Path Deep Links
- **General Path**: `imagine://path`
- **Specific Step**: `imagine://path/step/{{ path_next_step_id }}`
- **Celebration**: `imagine://path?celebration=true`

### UTM Parameters
Add these to track campaign effectiveness:
- `utm_source=onesignal`
- `utm_medium=push`
- `utm_campaign=path_engagement`
- `utm_content={{ journey_name }}`

## Testing Strategy

### 1. Create Test Segments
- Create test user segments to validate Journey flows
- Use your own device/account for testing

### 2. Test Journey Flows
1. **Not Started**: Clear all path progress and test onboarding
2. **In Progress**: Complete one step, wait, then test re-engagement
3. **Milestones**: Complete steps to reach 25%, 50%, 75%
4. **Completion**: Complete all steps

### 3. Validation Points
- ✅ Tags update correctly when steps are completed
- ✅ Journeys trigger at the right times
- ✅ Deep links navigate to correct screens
- ✅ Personalization variables populate correctly
- ✅ Users exit Journeys when conditions change

## Analytics & Optimization

### Key Metrics to Track
- **Journey Entry Rate**: How many users enter each Journey
- **Click-Through Rate**: Push notification → app open
- **Conversion Rate**: Journey → step completion
- **Time to Conversion**: Journey trigger → next step completion

### Optimization Opportunities
1. **A/B Test Message Copy**: Test different motivational approaches
2. **Timing Optimization**: Find optimal send times for your audience
3. **Channel Mix**: Test push vs. email vs. SMS effectiveness
4. **Frequency Capping**: Prevent over-messaging active users

## Implementation Checklist

### iOS App Setup ✅
- [x] PathAnalyticsHandler enhanced with OneSignal tagging
- [x] PathManager initializes tags on app start
- [x] PathEngagementManager handles daily inactivity updates
- [x] AppDelegate initializes engagement tracking

### OneSignal Dashboard Setup
- [ ] Create all required segments
- [ ] Build and test each Journey
- [ ] Set up proper time windows
- [ ] Configure deep links and UTM parameters
- [ ] Enable Journey analytics

### Testing & Launch
- [ ] Test all Journey flows with test accounts
- [ ] Validate tag updates and segment membership
- [ ] Verify deep link navigation
- [ ] Monitor initial performance metrics
- [ ] Iterate based on user engagement data

## Support & Troubleshooting

### Common Issues
1. **Tags not updating**: Check OneSignal initialization and user authentication
2. **Journeys not triggering**: Verify segment filters and entry rules
3. **Deep links not working**: Confirm URL scheme registration
4. **Personalization not working**: Check tag availability and spelling

### Debug Commands
In iOS app, you can manually trigger tag updates:
```swift
// Force update all tags
PathEngagementManager.shared.forceUpdateAllPathTags()

// Reset all tags (for testing)
PathEngagementManager.shared.resetAllPathTags()
```

This comprehensive setup will create a sophisticated automated engagement system that guides users through their mindfulness path while maximizing completion rates and long-term retention. 