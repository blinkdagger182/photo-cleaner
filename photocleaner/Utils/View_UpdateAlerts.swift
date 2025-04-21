import SwiftUI

extension View {
    func withUpdateAlerts(using updateService: UpdateService) -> some View {
        self
            .alert("Update Required", isPresented: Binding(get: {
                updateService.shouldForceUpdate
            }, set: { _ in })) {
                Button("Update Now") {
                    if let url = URL(string: "https://apps.apple.com/app/com.riskcreates.cln") {
                        UIApplication.shared.open(url)
                    }
                }
            } message: {
                Text(updateService.updateNotes ?? "A new version is required.")
            }
            .sheet(isPresented: Binding(get: {
                updateService.shouldShowOptionalUpdate
            }, set: { newValue in
                updateService.shouldShowOptionalUpdate = newValue
            })) {
                VStack(spacing: 16) {
                    Text("Update Available")
                        .font(.title2)
                    Text(updateService.updateNotes ?? "A new version is available.")
                    HStack {
                        Button("Maybe Later") {
                            updateService.shouldShowOptionalUpdate = false
                        }
                        Button("Update") {
                            if let url = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID") {
                                UIApplication.shared.open(url)
                            }
                        }
                    }
                }
                .padding()
            }
    }
}
