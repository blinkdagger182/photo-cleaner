# Photo Cleaner App

## RevenueCat Integration

This app integrates RevenueCat's SDK to provide subscription functionality with a built-in paywall. The integration includes:

1. **SDK Setup and Configuration**
   - RevenueCat is initialized in the app's entry point with your API key
   - User identification and proper attribution are configured

2. **Image View Tracking System**
   - The app tracks daily image view count using UserDefaults
   - A threshold system (30 images per day) is implemented
   - Counter resets at midnight each day

3. **Paywall Presentation**
   - When the threshold is reached, RevenueCat's built-in paywall is presented
   - Smooth modal presentation with appropriate animations
   - All paywall dismissal scenarios are handled gracefully

4. **Subscription Status Management**
   - SubscriptionManager class as an ObservableObject
   - CustomerInfo delegate methods to track subscription status
   - Premium status exposed via @EnvironmentObject
   - Entitlements checked on app launch
   - Paywall presentation skipped for subscribed users

## Setup Instructions

1. **Get a RevenueCat API Key**
   - Sign up at [RevenueCat](https://www.revenuecat.com/)
   - Create a project and get your API key
   - Configure your subscription offerings in the RevenueCat dashboard

2. **Update API Key**
   - Replace `YOUR_REVENUECAT_API_KEY` in `photocleanerApp.swift` with your actual API key

3. **Install Dependencies**
   - Run `swift package resolve` to install the RevenueCat SDK

## Testing

### Testing with RevenueCat's Sandbox Environment

1. **Enable Sandbox Mode**
   - RevenueCat automatically uses sandbox mode for App Store purchases during development

2. **Simulating the 30-Image Threshold**
   - Use the `ImageViewTracker.shared.simulateThresholdReached()` method in debug builds
   - Example: Add a button in development builds to trigger this method

```swift
#if DEBUG
Button("Simulate Threshold") {
    ImageViewTracker.shared.simulateThresholdReached()
}
#endif
```

3. **Testing Purchase Flow**
   - Use sandbox test accounts in App Store Connect
   - Test subscription renewal by setting short durations in RevenueCat dashboard

## Error Handling

The integration includes comprehensive error handling for:
- Network issues
- Offline scenarios for both subscription checks and purchases
- Purchase restoration
- Proper logging for debugging subscription issues
