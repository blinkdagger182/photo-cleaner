import SwiftUI
import Photos
import UIKit

struct PhotoGroupView: View {
    @ObservedObject var viewModel: PhotoGroupViewModel
    @EnvironmentObject var mainFlowCoordinator: MainFlowCoordinator
    
    @State private var fadeIn = false

    let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    HStack(alignment: .center) {
                        // Limited authorization banner
                        if viewModel.isLimitedAuthorization {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("You're viewing only selected photos.")
                                    .font(.subheadline)
                                    .foregroundColor(.primary)

                                Button("Add More Photos") {
                                    viewModel.presentLimitedLibraryPicker()
                                }
                                .buttonStyle(.bordered)

                                Button("Go to Settings to Allow Full Access") {
                                    viewModel.openSettings()
                                }
                                .font(.footnote)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.yellow.opacity(0.1))
                            .cornerRadius(12)
                        }

                        Spacer()

                        // App logo
                        VStack {
                            Spacer(minLength: 0)
                            Image(systemName: "photo.stack")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(height: 50)
                                .opacity(fadeIn ? 1 : 0)
                                .onAppear {
                                    withAnimation(.easeIn(duration: 0.5)) {
                                        fadeIn = true
                                    }
                                }
                            Spacer(minLength: 0)
                        }
                        .frame(height: 100)
                    }
                    .padding(.horizontal)
                    .padding(.top, 16)

                    // View mode selector
                    HStack(alignment: .bottom) {
                        Picker("View Mode", selection: $viewModel.viewByYear) {
                            Text("By Year").tag(true)
                            Text("My Albums").tag(false)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    .padding(.top, 12)
                    .padding(.bottom, 8)

                    // Main content
                    VStack(alignment: .leading, spacing: 20) {
                        if viewModel.viewByYear {
                            ForEach(viewModel.yearGroups) { yearGroup in
                                VStack(alignment: .leading, spacing: 12) {
                                    Text("\(yearGroup.year)")
                                        .font(.title)
                                        .bold()
                                        .padding(.horizontal)

                                    LazyVGrid(columns: columns, spacing: 16) {
                                        ForEach(yearGroup.months, id: \.id) { group in
                                            Button {
                                                mainFlowCoordinator.navigateToSwipeCards(photoGroupId: group.id.uuidString)
                                            } label: {
                                                AlbumCell(group: group)
                                            }
                                            .buttonStyle(.plain)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                        } else {
                            VStack(alignment: .leading, spacing: 16) {
                                sectionHeader(title: "My Albums")
                                LazyVGrid(columns: columns, spacing: 20) {
                                    ForEach(viewModel.savedAlbums, id: \.id) { group in
                                        Button {
                                            mainFlowCoordinator.navigateToSwipeCards(photoGroupId: group.id.uuidString)
                                        } label: {
                                            AlbumCell(group: group)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                                .padding(.horizontal)

                                Spacer(minLength: 40)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Photo Cleaner")
            .onAppear {
                viewModel.loadPhotoGroups()
            }
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