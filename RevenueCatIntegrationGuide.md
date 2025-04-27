# RevenueCat Integration Guide

## Adding RevenueCat SDK to Your Project

### Using Swift Package Manager in Xcode

1. In Xcode, select **File > Add Packages...**
2. Enter the RevenueCat SDK repository URL: `https://github.com/RevenueCat/purchases-ios.git`
3. Select the latest version (4.25.0 or newer)
4. Choose the "RevenueCat" product
5. Click **Add Package**

### Using CocoaPods

If you prefer CocoaPods, add this to your Podfile:

```ruby
pod 'RevenueCat', '~> 4.25.0'
```

Then run:

```bash
pod install
```

## Fixing Import Issues

After adding the package, make sure to import the correct modules:

- For Swift files: `import RevenueCat`
- For SwiftUI views: `import RevenueCat` and `import SwiftUI`

## Configuring Your App

1. Replace `YOUR_REVENUECAT_API_KEY` in `photocleanerApp.swift` with your actual API key from the RevenueCat dashboard.

2. Make sure to configure your subscription offerings in the RevenueCat dashboard.

3. For testing, use the sandbox environment which is automatically used during development.

## Simulating the 30-Image Threshold

You can use the debug method to simulate reaching the threshold:

```swift
#if DEBUG
ImageViewTracker.shared.simulateThresholdReached()
#endif
```

## Troubleshooting Common Issues

- **Missing Module Errors**: Make sure the RevenueCat package is properly added to your Xcode project
- **Build Errors**: Check that you're using a compatible version of the SDK for your iOS deployment target
- **Runtime Errors**: Verify your API key is correct and that you've configured offerings in the RevenueCat dashboard
