# RevenueCat Hosted Paywall Integration - Testing Guide

This guide provides instructions for testing the RevenueCat hosted paywall integration in the Photo Cleaner app.

## Prerequisites

1. RevenueCat account with configured offerings and products
2. Xcode 14+ with iOS 16+ simulator or device
3. Photo Cleaner app with the RevenueCat SDK integration

## Setup Instructions

### 1. Configure Your API Keys

Replace `YOUR_REVENUECAT_API_KEY` in `SubscriptionManager.swift` with:
- Your public SDK key from the RevenueCat dashboard for production
- Your sandbox environment key for testing

### 2. Configure Offering Identifier

Make sure the offering identifier in `SubscriptionManager.swift` matches what you've set up in the RevenueCat dashboard:

```swift
let offeringIdentifier = "default" // Replace with your actual offering identifier
```

### 3. Enable Sandbox Environment

To test purchases without actual charges, ensure you're using a sandbox environment:
- Use a test account on your device
- Use the simulator (automatically uses sandbox)

## Testing Scenarios

### 1. Basic Paywall Presentation

1. Launch the app
2. Swipe through 30 images (count is displayed in debug console)
3. Verify the RevenueCat hosted paywall appears automatically
4. Check that the paywall matches your configuration from the RevenueCat dashboard

### 2. Purchase Flow Testing

1. Trigger the paywall as described above
2. Select a subscription option
3. Complete the sandbox purchase flow
4. Verify:
   - Paywall automatically closes
   - User gains premium access
   - SwipeTracker count is reset
   - Paywall no longer appears regardless of swipe count

### 3. Restore Purchases

1. Complete a purchase as described above
2. Delete and reinstall the app
3. Tap "Restore Purchases" on the paywall
4. Verify that premium access is restored

### 4. Daily Reset Testing

1. Make note of current swipe count (displayed in debug console)
2. Change the system date on your device/simulator to the next day
3. Open the app again
4. Verify the swipe count has reset to 0

### 5. Error Handling

1. Put device in airplane mode
2. Trigger the paywall and attempt a purchase
3. Verify appropriate error handling and messaging

## Debugging

### Paywall Logger

The paywall logger is enabled in debug builds. Check the Xcode console for detailed logs:

```
PaywallLogger: [RevenueCatUI] [INFO] Paywall presented...
```

### Subscription Status

To verify subscription status in code:

```swift
let isSubscribed = SubscriptionManager.shared.isSubscribed
print("Is subscribed: \(isSubscribed)")
```

### SwipeTracker Information

To check current swipe count and threshold:

```swift
let count = SwipeTracker.shared.swipeCount
let remaining = SwipeTracker.shared.swipesRemainingUntilPaywall()
print("Current count: \(count), Remaining until paywall: \(remaining)")
```

## Common Issues and Solutions

### Paywall Not Appearing

- Verify SwipeTracker's `hasReachedLimit` is true
- Check `subscriptionManager.shouldShowPaywall()` returns true
- Ensure offering identifier matches what's in RevenueCat dashboard

### Purchase Failing

- Confirm you're using sandbox environment
- Verify products are active in App Store Connect
- Check RevenueCat dashboard for API errors

### Customization Issues

- Review the font provider configuration
- Check tint color settings in the app 