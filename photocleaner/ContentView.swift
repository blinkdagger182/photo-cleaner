import SwiftUI
import Photos
import UIKit
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var coordinator: AppCoordinator
    
    // We initially create this with nil parent, and set the parent in onAppear
    // This is necessary because we can't access the coordinator EnvironmentObject during initialization
    @StateObject private var mainFlowCoordinator = MainFlowCoordinator(parent: nil)
    
    var body: some View {
        ZStack {
            Group {
                switch photoManager.authorizationStatus {
                case .notDetermined:
                    RequestAccessView {
                        Task {
                            await photoManager.requestAuthorization()
                        }
                    }
                    .environmentObject(photoManager)
                    .environmentObject(toast)
                    .environmentObject(mainFlowCoordinator)

                case .authorized, .limited:
                    if photoManager.photoGroups.isEmpty {
                        // 🔍 If no albums are grouped, but assets exist (e.g. limited selection)
                        if !photoManager.allAssets.isEmpty {
                            let _ = print("✅ LimitedAccessView is active") // ✅ trick to inline-print
                            LimitedAccessView()
                                .environmentObject(photoManager)
                                .environmentObject(toast)
                                .environmentObject(coordinator)
                                .environmentObject(mainFlowCoordinator)
                        } else {
                            ContentUnavailableView("No Photos",
                                                   systemImage: "photo.on.rectangle",
                                                   description: Text("Your photo library is empty"))
                        }
                    } else {
                        PhotoGroupView()
                            .environmentObject(photoManager)
                            .environmentObject(toast)
                            .environmentObject(coordinator)
                            .environmentObject(mainFlowCoordinator)
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
        .modifier(WithModalCoordination(coordinator: coordinator.modalCoordinator))
        .environmentObject(photoManager)
        .environmentObject(toast)
        .environmentObject(mainFlowCoordinator)
        .onAppear {
            mainFlowCoordinator.parent = coordinator
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
