import SwiftUI
import Photos
import UIKit
import PhotosUI

struct LimitedAccessView: View {
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @EnvironmentObject var coordinator: AppCoordinator
    @EnvironmentObject var mainFlowCoordinator: MainFlowCoordinator
    
    @State private var shouldForceRefresh = false

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
                                PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: root)
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

                    let group = PhotoGroup(
                        id: UUID(),
                        assets: photoManager.allAssets,
                        title: "Selected Photos",
                        monthDate: nil
                    )

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        NavigationLink(destination: 
                            SwipeCardView(viewModel: SwipeCardViewModel(
                                group: group,
                                photoManager: photoManager,
                                forceRefresh: $shouldForceRefresh,
                                modalCoordinator: coordinator.modalCoordinator
                            ))
                            .environmentObject(photoManager)
                            .environmentObject(toast)
                            .environmentObject(coordinator)
                            .environmentObject(mainFlowCoordinator)
                        ) {
                            AlbumCell(group: group)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding()
                }
            }
        }
        .modifier(WithModalCoordination(coordinator: coordinator.modalCoordinator))
        .onAppear {
            print("👀 LimitedAccessView is visible")
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