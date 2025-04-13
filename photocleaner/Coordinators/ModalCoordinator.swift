import SwiftUI
import Photos

// Define the possible modal routes in the app
enum ModalRoute: Identifiable {
    case deletePreview(entries: [DeletePreviewEntry], forceRefresh: Binding<Bool>)
    case forceUpdate(notes: String?)
    case optionalUpdate(notes: String?, onDismiss: () -> Void)
    
    var id: String {
        switch self {
        case .deletePreview:
            return "deletePreview"
        case .forceUpdate:
            return "forceUpdate"
        case .optionalUpdate:
            return "optionalUpdate"
        }
    }
}

@MainActor
class ModalCoordinator: ObservableObject {
    @Published var activeRoute: ModalRoute?
    @Published var isPresenting: Bool = false
    
    // Convenience methods for showing modals
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
    
    // Method to dismiss any active route
    func dismiss() {
        isPresenting = false
        activeRoute = nil
    }
}

// View modifier to apply modal presentation with the coordinator
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
        switch route {
        case .deletePreview(let entries, let forceRefresh):
            DeletePreviewView(
                viewModel: DeletePreviewViewModel.create(
                    entries: entries,
                    onDismiss: {
                        // Toggle force refresh to update the view when dismissing
                        forceRefresh.wrappedValue.toggle()
                        coordinator.dismiss()
                    }
                )
            )
            .environmentObject(photoManager)
            .environmentObject(toast)
            .environmentObject(coordinator)
        
        case .forceUpdate(let notes):
            ForceUpdateOverlayView(notes: notes)
                .environmentObject(coordinator)
                .zIndex(1000) // Ensure it's on top
                .transition(.identity) // No animation for force update
        
        case .optionalUpdate(let notes, let onDismiss):
            OptionalUpdateSheet(
                notes: notes,
                onDismiss: {
                    onDismiss()
                    coordinator.dismiss()
                }
            )
            .environmentObject(coordinator)
            .background(Color(.systemBackground))
            .cornerRadius(16)
            .padding()
        }
    }
}

// Extension for View to apply the modal coordinator
extension View {
    func withModalCoordination(_ coordinator: ModalCoordinator) -> some View {
        self.modifier(WithModalCoordination(coordinator: coordinator))
    }
} 
