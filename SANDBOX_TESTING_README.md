# Sandbox Testing Guide: Discover Tab Paywall

This document outlines the steps to test the paywall functionality implemented specifically within the **Discover** tab of the Photo Cleaner app using an Apple Sandbox account.

## Feature Description

The Discover tab allows users to swipe through photos. For users without an active subscription, a paywall is presented after they have swiped 5 photos (left or right) within a single app session. This paywall uses the standard RevenueCat UI offering.

## Prerequisites

*   An Apple **Sandbox Tester Account**. You can create one in App Store Connect.
*   The Photo Cleaner app installed on a test device.

## Testing Steps

### Scenario 1: Non-Subscribed User (Paywall Trigger)

1.  **Log In:** Ensure you are logged into the test device with your Sandbox Tester Account.
2.  **Clear Previous Subscription (If Any):** Make sure this Sandbox account does *not* have an active subscription for this app. If it does, you might need to manage sandbox subscriptions or use a different sandbox account.
3.  **Launch App:** Open the Photo Cleaner app.
4.  **Navigate:** Go to the **Discover** tab (icon: ✨).
5.  **Swipe Photos:** Swipe either left or right on 5 photos.
6.  **Observe:** After the 5th swipe action is completed, the RevenueCat paywall screen should automatically appear.
7.  **Verify Session Limit:** Close the paywall. Continue swiping. The paywall should *not* reappear during this same app session.

### Scenario 2: Subscribed User (No Paywall)

1.  **Log In:** Ensure you are logged into the test device with a Sandbox Tester Account that **has an active subscription** for this app (either purchased previously during testing or via RevenueCat's dashboard/StoreKit configuration).
2.  **Launch App:** Open the Photo Cleaner app.
3.  **Navigate:** Go to the **Discover** tab.
4.  **Swipe Photos:** Swipe past 5 photos (e.g., swipe 6 or more times).
5.  **Observe:** The paywall should **not** appear at any point.

## Important Notes

*   This paywall logic is **exclusive to the Discover tab**. It does not affect functionality in the Library tab.
*   The paywall is designed to appear only **once per app session** for non-subscribed users after hitting the 5-swipe limit.

These steps should allow App Store reviewers to verify the correct implementation of the conditional paywall within the Discover feature using a sandbox environment.
