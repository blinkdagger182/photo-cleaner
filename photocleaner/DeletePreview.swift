import SwiftUI
import Photos
import AVFoundation

struct DeletePreviewEntry: Identifiable, Equatable, Hashable {
    let id = UUID()
    let asset: PHAsset
    let image: UIImage
    let fileSize: Int

    static func == (lhs: DeletePreviewEntry, rhs: DeletePreviewEntry) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

struct DeletePreviewView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var photoManager: PhotoManager
    @EnvironmentObject var toast: ToastService
    @Binding var entries: [DeletePreviewEntry]
    @Binding var forceRefresh: Bool
    @State private var isLoading = false
    
    @State private var selectedEntries: Set<UUID> = []
    @State private var isDeleting = false
    @State private var deletionComplete = false

    var selectedCount: Int {
        selectedEntries.count
    }

    var totalSize: Int {
        entries.filter { selectedEntries.contains($0.id) }.map { $0.fileSize }.reduce(0, +)
    }

    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: Int64(totalSize), countStyle: .file)
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack {
                Spacer()
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(.primary)
                }
                .padding([.top, .trailing], 16)
            }

            Text("Ready to Clean Up?").font(.title).bold()
            Text("You're about to delete \(selectedCount) photos\nFree up to \(formattedSize) of storage.")
                .multilineTextAlignment(.center)
                .font(.subheadline)

            if entries.isEmpty {
                // Show a loading state if there are no entries yet
                VStack(spacing: 20) {
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Loading deleted photos...")
                        .foregroundColor(.secondary)
                }
                .frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 12) {
                        ForEach(entries) { entry in
                            let isSelected = selectedEntries.contains(entry.id)
                            Image(uiImage: entry.image)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 100, height: 100)
                                .clipped()
                                .overlay(
                                    isSelected ? Color.black.opacity(0.25) : Color.clear
                                )
                                .overlay(
                                    isSelected ? Image(systemName: "checkmark.circle.fill")
                                        .foregroundColor(.blue)
                                        .padding(6) : nil,
                                    alignment: .topTrailing
                                )
                                .onTapGesture {
                                    if isSelected {
                                        selectedEntries.remove(entry.id)
                                    } else {
                                        selectedEntries.insert(entry.id)
                                    }
                                }
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }

            if deletionComplete {
                Label("Deleted", systemImage: "checkmark.circle.fill")
                    .font(.headline)
                    .foregroundColor(.green)
            } else if isDeleting {
                ProgressView("Deleting…")
            } else {
                Button(action: deleteSelectedPhotos) {
                    Text("Delete")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                        .padding(.horizontal)
                }
                .disabled(entries.isEmpty || selectedEntries.isEmpty)
                .opacity(entries.isEmpty || selectedEntries.isEmpty ? 0.5 : 1)
            }
        }
        .padding()
        .onAppear {
            // Start in a loading state if entries is empty but we have marked assets
            isLoading = entries.isEmpty && !photoManager.markedForDeletion.isEmpty
            
            // Select all entries by default when view appears
            selectedEntries = Set(entries.map { $0.id })
        }
        .onChange(of: entries) { newEntries in
            // When entries are loaded, update the selected entries
            if !newEntries.isEmpty && selectedEntries.isEmpty {
                selectedEntries = Set(newEntries.map { $0.id })
                isLoading = false
            }
        }
    }

    private func deleteSelectedPhotos() {
        isDeleting = true
        let toDelete = entries.filter { selectedEntries.contains($0.id) }
        let assetsToDelete = toDelete.map { $0.asset }

        Task {
            // Wait for the hardDeleteAssets operation and get the success status
            let deletionSucceeded = await photoManager.hardDeleteAssets(assetsToDelete)

            await MainActor.run {
                if deletionSucceeded {
                    // Deletion was successful - update UI accordingly
                    isDeleting = false
                    deletionComplete = true
                    
                    // Play success sound when deletion completes and we show the green tick
                    SoundManager.shared.playSound(named: "air-whoosh")
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                        dismiss()
                        forceRefresh.toggle()
                    }
                } else {
                    // Deletion failed or was canceled by user - reset UI and inform user
                    isDeleting = false
                    
                    // Show toast message about deletion failure/cancellation
                    toast.show("Deletion was canceled or failed. Your photos were not deleted.", duration: 2.0)
                }
            }
        }
    }
}
