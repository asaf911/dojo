# Mixpanel Identity Management Test Plan

## Overview

This document outlines the test procedures for verifying the simplified Mixpanel identity management flow. The new approach uses Mixpanel's device_id as the initial distinct_id, then directly transitions to using Firebase's user ID on signup/login without a separate guest ID.

## Test Scenarios

### 1. Basic Identity Flow

**Objective**: Verify that anonymous events are properly associated with user after signup.

**Steps**:
1. Clear app data/reinstall app to start fresh
2. Launch app as a new user
3. Track an event (e.g., browse meditation content)
4. In Mixpanel Live View, verify event appears under a device_id
5. Sign up with a new account
6. Verify in Mixpanel that:
   - Previous event now appears under user ID (Firebase UID)
   - All new events appear under user ID
   - User profile shows both pre-signup and post-signup events

**Expected Result**: All events, including those before signup, should be associated with the authenticated user ID.

### 2. Logout and Login Flow

**Objective**: Verify that the distinct_id persists across logout/login cycles and events are properly associated.

**Steps**:
1. Login to account A
2. Track events
3. Logout
4. Track events as anonymous user
5. Login to account B
6. Track events
7. Check Mixpanel:
   - Verify events from account A appear under account A's user ID
   - Verify anonymous events after logout appear under account B
   - Verify events after login to account B appear under account B

**Expected Result**: 
- Events tracked while logged in as account A should be associated with account A's user ID
- Events tracked while logged out should be associated with account B after logging into account B
- No events should be lost or misattributed

### 3. Reinstallation Scenario

**Objective**: Verify behavior after app reinstallation.

**Steps**:
1. Login to an account and track events
2. Uninstall and reinstall app
3. Track events as anonymous user
4. Login with the same account
5. Check in Mixpanel:
   - Verify pre-reinstall events are still linked to the user ID
   - Verify post-reinstall anonymous events are now linked to the user ID

**Expected Result**: Pre-reinstall authenticated events should remain linked to the user ID. Post-reinstall anonymous events should be associated with the user ID after login.

### 4. API Verification

**Objective**: Verify correct identity transitions using Mixpanel's API.

**Steps**:
1. Use Mixpanel's [Export API](https://developer.mixpanel.com/reference/raw-data-export-api) to export events for a test user
2. Look for `$identify` events showing transitions from device_id to user ID
3. Verify the event history shows proper chronological flow from anonymous to authenticated

**Expected Result**: The API should show clear identity transitions with proper aliasing from device_id to authenticated user ID.

## Implementation Verification

Check the following implementation details:

1. **AppDelegate.swift**:
   - Verify Mixpanel initialization does not override the device_id
   - Check that identify() is only called for already authenticated users

2. **UserIdentityManager.swift**:
   - Confirm removal of guest ID generation for Mixpanel
   - Verify simplified identify method

3. **AuthViewModel.swift**:
   - Confirm logout method does not reset Mixpanel's distinct_id
   - Verify login method correctly identifies with Firebase UID

4. **SignUpViewModel.swift**:
   - Verify direct identification with Firebase UID on signup

## Troubleshooting

If identity merging issues occur:

1. Check Mixpanel dashboard for distinct_id distribution
2. Verify the sequence of identify() calls in the app logs
3. Use Mixpanel's debug mode to trace identity transitions

## Expected Benefits

- Simplified identity management code
- More accurate user journey tracking
- Cleaner transition from anonymous to authenticated user
- Fewer edge cases and data inconsistencies 