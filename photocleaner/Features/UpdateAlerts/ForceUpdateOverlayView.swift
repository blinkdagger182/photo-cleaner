import SwiftUI

// A simpler protocol for the overlay view to use
protocol UpdateActionHandler {
    func openAppStore()
}

// Make UpdateCoordinator conform to the protocol
extension UpdateCoordinator: UpdateActionHandler {}

// Create a simple handler for modal use
class SimpleUpdateHandler: UpdateActionHandler {
    func openAppStore() {
        if let url = UpdateService.shared.appStoreURL {
            UIApplication.shared.open(url)
        }
    }
}

struct ForceUpdateOverlayView: View {
    let coordinator: UpdateActionHandler
    var notes: String?
    
    // Original initializer
    init(coordinator: UpdateCoordinator) {
        self.coordinator = coordinator
        self.notes = nil
    }
    
    // Alternative initializer for modal use
    init(notes: String?) {
        self.notes = notes
        self.coordinator = SimpleUpdateHandler()
    }
    
    var body: some View {
        ZStack {
            Color.black.opacity(0.8)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 24) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.yellow)
                
                Text("Update Required")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text(notes ?? "This version is no longer supported. Please update to continue using the app.")
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.white)
                    .padding(.horizontal)
                
                Button(action: {
                    coordinator.openAppStore()
                }) {
                    Text("Update Now")
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal, 40)
                .padding(.top, 20)
            }
            .padding()
            .background(Color.gray.opacity(0.3))
            .cornerRadius(16)
            .padding(30)
        }
    }
} 