# PhotoCleaner

PhotoCleaner is a SwiftUI app that helps users organize and clean up their photo library through a simple swipe-based interface.

## Architecture

The app follows a coordinator-based architecture with the following main components:

### Coordinators

- **AppCoordinator**: Manages the main routing between onboarding, splash, and main screens
- **MainFlowCoordinator**: Handles navigation within the main flow (photo group browsing, swiping, modals)
- **UpdateCoordinator**: Manages the optional and force update flows

### Features

The app is organized into feature modules:

- **Onboarding**: Initial user flow to get photo permissions
- **Splash**: Loading screen that shows while the app initializes
- **Home**: Main photo groups browsing view
- **Swipe**: Card-based swiping interface for photo organization
- **DeletePreview**: Confirmation view before permanently deleting photos
- **UpdateAlerts**: System for showing update notifications

### Services

- **PhotoLibraryService**: Handles PhotoKit access and album organization
- **AlbumManager**: Manages system album creation and modification
- **PhotoManager**: Combines photo services and maintains global photo state
- **ToastService**: Provides in-app notifications
- **UpdateService**: Handles app update checks and version management

## Getting Started

1. Clone the repository
2. Open `photocleaner.xcodeproj` in Xcode
3. Build and run on a simulator or device
