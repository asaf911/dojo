# Optimized Rating Analytics System

## Overview
The rating system has been optimized to provide simple, actionable data for Mixpanel analytics while maintaining all existing functionality.

## Key Improvements

### 1. Simplified Event Structure
**Before** (complex event with redundant data):
```swift
AnalyticsManager.shared.logEvent("practice_session_rated", parameters: [
    "practice_id": practiceId,
    "practice_title": practiceTitle,
    "practice_duration_minutes": practiceDurationMinutes,
    "rating_value": rating,
    "rating_label": ratingLabel,        // Redundant - can derive from rating
    "rating_scale": "1-5_numbers",      // Static - not needed
    "source": "post_practice_view"      // Always same - not needed
])
```

**After** (clean, focused event):
```swift
AnalyticsManager.shared.logEvent("practice_rated", parameters: [
    "practice_id": practiceId,
    "practice_name": practiceTitle,
    "practice_category": practiceCategory,  // NEW: Essential for sorting by type
    "practice_duration_minutes": practiceDurationMinutes,
    "rating": rating                        // Direct 1-5 value
])
```

### 2. Immediate Analytics Firing
- **Before**: Analytics only fired when user left the PostPracticeView
- **After**: Analytics fire immediately when user selects a rating
- **Benefit**: More accurate data capture, no lost events if user closes app

### 3. Essential Data for Your Use Case
The new event structure includes exactly what you need to analyze in Mixpanel:

| Field | Purpose | Example |
|-------|---------|---------|
| `practice_name` | Practice identifier for sorting | "Morning Clarity" |
| `practice_category` | Practice type for grouping | "relax", "focus", "imagine" |
| `rating` | 1-5 rating value | 4 |
| `practice_duration_minutes` | Filter by length | 10 |

## Mixpanel Analysis Capabilities

### Top Rated Practices Overall
```sql
SELECT practice_name, AVG(rating) as avg_rating, COUNT(*) as total_ratings
FROM practice_rated 
GROUP BY practice_name 
ORDER BY avg_rating DESC, total_ratings DESC
```

### Top Rated Practices by Category
```sql
SELECT practice_category, practice_name, AVG(rating) as avg_rating, COUNT(*) as total_ratings
FROM practice_rated 
GROUP BY practice_category, practice_name 
ORDER BY practice_category, avg_rating DESC
```

### Category Performance
```sql
SELECT practice_category, AVG(rating) as avg_rating, COUNT(*) as total_ratings
FROM practice_rated 
GROUP BY practice_category 
ORDER BY avg_rating DESC
```

### Duration vs Rating Analysis
```sql
SELECT practice_duration_minutes, AVG(rating) as avg_rating, COUNT(*) as total_ratings
FROM practice_rated 
GROUP BY practice_duration_minutes 
ORDER BY practice_duration_minutes
```

## Implementation Details

### Rating Component
- **File**: `PostPracticeRatingView.swift`
- **New Parameters**: Added `practiceCategory: String`
- **Analytics Method**: `logRatingEventOptimized()` called immediately on rating selection
- **Backward Compatibility**: Legacy `logRatingEvent()` method maintained but deprecated

### Parent View Integration
- **File**: `PostPracticeView.swift`
- **Change**: Passes `completedFile.category.rawValue` to rating component
- **Removed**: Redundant analytics call in `onDisappear`

### Available Categories
Based on `AudioCategory.swift`:
- `relax` - Relaxation practices
- `focus` - Focus/concentration practices  
- `imagine` - Imagination/visualization practices
- `general` - General meditation
- `learn` - Learning/educational content
- `routines` - Daily routine practices
- `deepdive` - Advanced/longer practices

## User Experience
- No changes to user interface or interactions
- Same 1-5 rating scale with visual feedback
- Haptic feedback still provided
- Single rating per practice still enforced

## Testing
1. Complete any practice session
2. Rate the practice (1-5)
3. Verify immediate analytics event in logs/Mixpanel
4. Check that all parameters are present and correct

## Future Enhancements
- Could add user demographics data if needed
- Could include completion percentage at rating time
- Could add time-of-day rating patterns
- Could track rating trends over time per practice

## Conclusion
This optimized system provides exactly the data you need to identify your best practices by category and overall rating, while maintaining a clean, simple event structure that's easy to analyze in Mixpanel. 