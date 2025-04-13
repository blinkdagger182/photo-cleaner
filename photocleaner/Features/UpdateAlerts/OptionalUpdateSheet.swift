import SwiftUI

// A simple protocol abstraction for update operations
protocol UpdateCoordinatorProtocol {
    func hideOptionalUpdateSheet()
    func openAppStore()
}

// Make standard UpdateCoordinator conform to protocol
extension UpdateCoordinator: UpdateCoordinatorProtocol {}

// Simple coordinator for modal use
class ModalUpdateCoordinator: UpdateCoordinatorProtocol {
    var onDismiss: () -> Void
    
    init(onDismiss: @escaping () -> Void) {
        self.onDismiss = onDismiss
    }
    
    func hideOptionalUpdateSheet() {
        onDismiss()
    }
    
    func openAppStore() {
        if let url = UpdateService.shared.appStoreURL {
            UIApplication.shared.open(url)
        }
        onDismiss()
    }
}

struct OptionalUpdateSheet: View {
    let version: AppVersion
    var coordinator: UpdateCoordinatorProtocol
    
    // Original initializer
    init(version: AppVersion, coordinator: UpdateCoordinator) {
        self.version = version
        self.coordinator = coordinator
    }
    
    // Alternative initializer for modal use
    init(notes: String?, onDismiss: @escaping () -> Void) {
        // Create a default AppVersion with the provided notes
        self.version = AppVersion(
            platform: "ios",
            version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            is_valid: true,
            is_latest: false,
            notes: notes
        )
        
        // Use a simple coordinator for modal presentation
        self.coordinator = ModalUpdateCoordinator(onDismiss: onDismiss)
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 12) {
                Image(systemName: "arrow.up.circle.fill")
                    .resizable()
                    .frame(width: 60, height: 60)
                    .foregroundColor(.blue)
                
                Text("Update Available")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("Version \(version.version) is available")
                    .font(.headline)
                    .foregroundColor(.secondary)
            }
            
            if let notes = version.notes {
                VStack(alignment: .leading, spacing: 8) {
                    Text("What's New:")
                        .font(.headline)
                    
                    Text(notes)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
            
            Spacer()
            
            HStack(spacing: 16) {
                Button("Not Now") {
                    coordinator.hideOptionalUpdateSheet()
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                
                Button("Update") {
                    coordinator.openAppStore()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding(.bottom)
        }
        .padding()
        .frame(maxWidth: 500)
    }
} 