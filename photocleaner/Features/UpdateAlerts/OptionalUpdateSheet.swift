import SwiftUI

struct OptionalUpdateSheet: View {
    let version: AppVersion
    let coordinator: UpdateCoordinator
    
    var body: some View {
        VStack(spacing: 20) {
            // Title
            Text("Update Available")
                .font(.title2)
                .fontWeight(.bold)
            
            // Version info
            Text("Version \(version.version) is available")
                .font(.headline)
            
            // Notes
            if let notes = version.notes {
                Text(notes)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.gray.opacity(0.1))
                    )
            }
            
            // Action buttons
            HStack(spacing: 16) {
                Button("Not Now") {
                    coordinator.hideOptionalUpdateSheet()
                }
                .buttonStyle(.bordered)
                
                Button("Update") {
                    coordinator.openAppStore()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top)
        }
        .padding()
        .frame(maxWidth: 400)
    }
} 