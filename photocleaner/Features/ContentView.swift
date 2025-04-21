import SwiftUI
import Photos
import UIKit
import PhotosUI

struct ContentView: View {
    @EnvironmentObject private var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = true
    
    var body: some View {
        Group {
            switch photoManager.authorizationStatus {
            case .notDetermined:
                RequestAccessView {
                    Task {
                        await photoManager.requestAuthorization()
                    }
                }

            case .authorized, .limited:
                if photoManager.photoGroups.isEmpty {
                    // 🔍 If no albums are grouped, but assets exist (e.g. limited selection)
                    if !photoManager.allAssets.isEmpty {
                        let _ = print("✅ LimitedAccessView is active") // ✅ trick to inline-print
                        LimitedAccessView()
                    } else {
                        ContentUnavailableView("No Photos",
                                               systemImage: "photo.on.rectangle",
                                               description: Text("Your photo library is empty")).overlay(
                        Button("Open Settings") {
                            if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(settingsURL)
                            }
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.primary.opacity(0.9))
                        .foregroundColor(Color(UIColor.systemBackground))
                        .cornerRadius(16)
                        .padding(.horizontal, 32)
                        .padding(.bottom, 20),
                        alignment: .bottom
                    )
                    }
                } else {
                    // Pass photoManager to PhotoGroupView for proper initialization of the ViewModel
                    PhotoGroupView(photoManager: photoManager)
                        .environmentObject(photoManager)
                        .environmentObject(toast)
                }

            case .denied, .restricted:
                ContentUnavailableView("No Access to Photos",
                                       systemImage: "lock.fill",
                                       description: Text("Please enable photo access in Settings"))
                .overlay(
                    Button("Open Settings") {
                        if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(settingsURL)
                        }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.primary.opacity(0.9))
                    .foregroundColor(Color(UIColor.systemBackground))
                    .cornerRadius(16)
                    .padding(.horizontal, 32)
                    .padding(.bottom, 20),
                    alignment: .bottom
                )

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

struct LimitedAccessView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @StateObject private var viewModel = LimitedAccessViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    
                    // 🔔 Banner: Only viewing selected photos
                    VStack(alignment: .leading, spacing: 8) {
                        Text("You're viewing only selected photos.")
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Button(action: {
                            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                               let root = scene.windows.first?.rootViewController {
                                viewModel.openPhotoLibraryPicker(from: root)
                            }
                        }) {
                            Text("Add More Photos")
                                .font(.subheadline)
                                .bold()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding()
                    .background(Color.yellow.opacity(0.1))
                    .cornerRadius(12)
                    .padding(.horizontal)
                    
                    // 📸 Section header
                    sectionHeader(title: "Selected Photos")

                    let group = viewModel.createPhotoGroup(with: photoManager.allAssets)

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        AlbumCell(group: group)
                            .onTapGesture {
                                viewModel.selectedGroup = group
                            }
                    }
                    .padding()
                }
            }

        }
        .sheet(item: $viewModel.selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: $viewModel.forceRefresh)
                .environmentObject(photoManager)
                .environmentObject(toast)
        }
        .onAppear {
            print("👀 LimitedAccessView is visible")
            viewModel.onAppear()
        }
    }

    private func sectionHeader(title: String) -> some View {
        HStack {
            Text(title)
                .font(.title2)
                .bold()
            Spacer()
        }
        .padding(.horizontal)
    }
}

@MainActor
class LimitedAccessViewModel: ObservableObject {
    @Published var selectedGroup: PhotoGroup?
    @Published var forceRefresh = false
    
    func onAppear() {
        // Any initialization logic that needs to happen when the view appears
    }
    
    func openPhotoLibraryPicker(from viewController: UIViewController) {
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: viewController)
    }
    
    func createPhotoGroup(with assets: [PHAsset]) -> PhotoGroup {
        return PhotoGroup(
            id: UUID(),
            assets: assets,
            title: "Selected Photos",
            monthDate: nil
        )
    }
}
