import SwiftUI
import Photos
import UIKit

struct ContentView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService

    var body: some View {
        Group {
            switch photoManager.authorizationStatus {
            case .notDetermined:
                RequestAccessView {
                    Task {
                        await photoManager.requestAuthorization()
                    }
                }
            case .authorized:
                if photoManager.photoGroups.isEmpty {
                    ContentUnavailableView("No Photos",
                        systemImage: "photo.on.rectangle",
                        description: Text("Your photo library is empty"))
                } else {
                    PhotoGroupView()
                        .environmentObject(photoManager)
                        .environmentObject(toast)
                }
            case .denied, .restricted:
                ContentUnavailableView("No Access to Photos",
                    systemImage: "lock.fill",
                    description: Text("Please enable photo access in Settings"))
            @unknown default:
                EmptyView()
            }
        }
    }
}


struct RequestAccessView: View {
    let onRequest: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 50))
            Text("Photo Access Required")
                .font(.title)
            Text("This app needs access to your photos to help you clean up similar photos")
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Grant Access") {
                onRequest()
            }
            .buttonStyle(.borderedProminent)
        }
    }
}
