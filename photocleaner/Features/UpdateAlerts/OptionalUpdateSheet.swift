import SwiftUI

struct OptionalUpdateSheet: View {
    let version: AppVersion
    let coordinator: UpdateCoordinator
    
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
                    coordinator.hideOptionalUpdateSheet()
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