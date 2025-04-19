# RevenueCat Integration Instructions

Follow these steps to add RevenueCat to your Photo Cleaner project:

## Adding RevenueCat via Swift Package Manager

1. Open the Photo Cleaner project in Xcode.
2. Go to **File > Add Packages...**
3. In the search bar, paste the RevenueCat repository URL: 
   ```
   https://github.com/RevenueCat/purchases-ios.git
   ```
4. Click **Add Package**
5. In the package options, select **RevenueCat** to add to your target.
6. Click **Add Package** to confirm.

## Configuring RevenueCat

1. Replace `YOUR_REVENUECAT_API_KEY` in `SubscriptionManager.swift` with your actual API key from the RevenueCat dashboard.

2. Make sure your products are properly configured in App Store Connect and RevenueCat dashboard with the following attributes:
   - Monthly subscription
   - Annual subscription

## Implementation Details

This implementation includes:

1. **Subscription management:** Using `SubscriptionManager.swift` to handle purchases and subscription status checking.

2. **Swipe counting with daily reset:** The `SwipeTracker.swift` class counts image views and resets the counter daily.

3. **Paywall presentation:** A paywall is shown after the user swipes through 30 images, with the counter resetting daily.

## Testing the Paywall

To test the paywall functionality:
1. Run the app
2. Swipe through images until you reach 30 swipes
3. The paywall should appear automatically
4. To reset the counter for testing, you can either:
   - Wait until the next day (midnight in the user's local time)
   - Or manually reset using `SwipeTracker.shared.resetSwipeCount()` in debug mode 