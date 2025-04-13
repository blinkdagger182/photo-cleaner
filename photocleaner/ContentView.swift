import SwiftUI
import Photos
import UIKit
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var coordinator: AppCoordinator

    var body: some View {
        mainContent
            .modifier(WithModalCoordination(coordinator: coordinator.modalCoordinator))
            .environmentObject(photoManager)
            .environmentObject(toast)
    }
    
    @ViewBuilder
    private var mainContent: some View {
        if photoManager.authorizationStatus == .notDetermined {
            RequestAccessView {
                Task {
                    await photoManager.requestAuthorization()
                }
            }
            .environmentObject(photoManager)
            .environmentObject(toast)
        } else if photoManager.authorizationStatus == .authorized || photoManager.authorizationStatus == .limited {
            if photoManager.photoGroups.isEmpty {
                if !photoManager.allAssets.isEmpty {
                    let _ = print("✅ LimitedAccessView is active")
                    LimitedAccessView()
                        .environmentObject(photoManager)
                        .environmentObject(toast)
                        .environmentObject(coordinator)
                } else {
                    EmptyPhotoStateView()
                }
            } else {
                PhotoGroupView(viewModel: PhotoGroupViewModel(coordinator: coordinator.mainFlowCoordinator))
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .environmentObject(coordinator)
            }
        } else if photoManager.authorizationStatus == .denied || photoManager.authorizationStatus == .restricted {
            NoAccessView()
        } else {
            // @unknown default case
            EmptyView()
        }
    }
}

// Empty photo library state view
struct EmptyPhotoStateView: View {
    var body: some View {
        VStack {
            Image(systemName: "photo.on.rectangle")
                .font(.system(size: 70))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            
            Text("No Photos")
                .font(.title2)
                .bold()
            
            Text("Your photo library is empty")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}

// No access to photos view
struct NoAccessView: View {
    var body: some View {
        VStack {
            Image(systemName: "lock.fill")
                .font(.system(size: 70))
                .foregroundStyle(.secondary)
                .padding(.bottom, 8)
            
            Text("No Access to Photos")
                .font(.title2)
                .bold()
            
            Text("Please enable photo access in Settings")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
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
