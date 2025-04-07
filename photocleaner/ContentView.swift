import SwiftUI
import Photos
import UIKit
import PhotosUI

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

            case .authorized, .limited:
                if photoManager.photoGroups.isEmpty {
                    // 🔍 If no albums are grouped, but assets exist (e.g. limited selection)
                    if !photoManager.allAssets.isEmpty {
                        LimitedAccessView()
                    } else {
                        ContentUnavailableView("No Photos",
                                               systemImage: "photo.on.rectangle",
                                               description: Text("Your photo library is empty"))
                    }
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

struct LimitedAccessView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService

    @State private var selectedGroup: PhotoGroup?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    sectionHeader(title: "Selected Photos")

                    let group = PhotoGroup(
                        id: UUID(),
                        assets: photoManager.allAssets,
                        title: "Selected Photos",
                        monthDate: nil
                    )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        AlbumCell(group: group)
                            .onTapGesture {
                                selectedGroup = group
                            }
                    }
                    .padding()

                    Button("Manage Access") {
                        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                           let root = scene.windows.first?.rootViewController {
                            PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
                        }
                    }
                    .padding()
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(item: $selectedGroup) { group in
            SwipeCardView(group: group, forceRefresh: .constant(false))
                .environmentObject(photoManager)
                .environmentObject(toast)
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
