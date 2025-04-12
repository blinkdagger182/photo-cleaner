# Modal Coordinator Pattern Implementation

## Overview

The Modal Coordinator pattern has been implemented to centralize and standardize the presentation of modal views in the app. This pattern provides several advantages:

1. **Centralized Control**: All modal presentations are managed through a single coordinator.
2. **Type-Safe Routing**: Using an enum-based routing system for modals.
3. **Consistent Presentation**: Modals are presented with consistent animations and styling.
4. **Better State Management**: No more scattered presentation state flags across view models.

## Key Components

### ModalRoute Enum

The `ModalRoute` enum defines all possible modal routes with their associated data:

```swift
enum ModalRoute: Identifiable {
    case deletePreview(entries: [DeletePreviewEntry], forceRefresh: Binding<Bool>)
    case forceUpdate(notes: String?)
    case optionalUpdate(notes: String?, onDismiss: () -> Void)
    
    var id: String {
        switch self {
        case .deletePreview: return "deletePreview"
        case .forceUpdate: return "forceUpdate"
        case .optionalUpdate: return "optionalUpdate"
        }
    }
}
```

### ModalCoordinator Class

The `ModalCoordinator` manages the presentation state and provides methods for showing different types of modals:

```swift
@MainActor
class ModalCoordinator: ObservableObject {
    @Published var activeRoute: ModalRoute?
    @Published var isPresenting: Bool = false
    
    func showDeletePreview(entries: [DeletePreviewEntry], forceRefresh: Binding<Bool>) {
        activeRoute = .deletePreview(entries: entries, forceRefresh: forceRefresh)
        isPresenting = true
    }
    
    func showForceUpdate(notes: String?) {
        activeRoute = .forceUpdate(notes: notes)
        isPresenting = true
    }
    
    func showOptionalUpdate(notes: String?, onDismiss: @escaping () -> Void) {
        activeRoute = .optionalUpdate(notes: notes, onDismiss: onDismiss)
        isPresenting = true
    }
    
    func dismiss() {
        isPresenting = false
        activeRoute = nil
    }
}
```

### WithModalCoordination ViewModifier

This view modifier applies the modal presentation to any view:

```swift
struct WithModalCoordination: ViewModifier {
    @ObservedObject var coordinator: ModalCoordinator
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    
    func body(content: Content) -> some View {
        content
            .overlay(
                ZStack {
                    if coordinator.isPresenting, let route = coordinator.activeRoute {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                            .onTapGesture {
                                // Force update should block interaction
                                if case .forceUpdate = route {
                                    // Do nothing - block dismissal
                                } else {
                                    coordinator.dismiss()
                                }
                            }
                        
                        modalView(for: route)
                            .transition(.opacity.combined(with: .move(edge: .bottom)))
                    }
                }
                .animation(.spring(), value: coordinator.isPresenting)
            )
    }
    
    @ViewBuilder
    private func modalView(for route: ModalRoute) -> some View {
        // Returns the appropriate view for each route...
    }
}
```

## Usage

### Integration with AppCoordinator

The `ModalCoordinator` is integrated with the `AppCoordinator`:

```swift
class AppCoordinator: ObservableObject {
    // Other properties...
    let modalCoordinator: ModalCoordinator
    
    @MainActor
    init() {
        // Initialize services...
        self.modalCoordinator = ModalCoordinator()
        // ...
    }
}
```

### Showing a Modal

To show a modal from any view or view model:

```swift
// In a view with access to the AppCoordinator
@EnvironmentObject var coordinator: AppCoordinator

// Then, to show a modal:
coordinator.modalCoordinator.showDeletePreview(entries: entries, forceRefresh: $forceRefresh)

// Or for ForceUpdate:
coordinator.modalCoordinator.showForceUpdate(notes: updateNotes)

// Or for OptionalUpdate:
coordinator.modalCoordinator.showOptionalUpdate(notes: updateNotes) {
    // Dismiss action code
}
```

### Applying the Coordinator

The modal coordinator is applied to views using the `withModalCoordination` modifier:

```swift
.withModalCoordination(coordinator.modalCoordinator)
```

This is typically added to the root view to enable modals throughout the app, but can also be added to specific subviews if needed.

## Benefits

1. **Clean Interface**: No more scattered `.sheet` and `.fullScreenCover` modifiers
2. **Improved Navigation Flow**: Modal presentation logic is decoupled from views
3. **Consistent User Experience**: All modals behave similarly
4. **Interactive Dismissal Control**: ForceUpdate can block dismissal by tapping outside
5. **Centralized Presentation Logic**: All modal presentation code is in one place 