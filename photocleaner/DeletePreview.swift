import SwiftUI
import Photos

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
                    }
                }
                .padding(.horizontal)
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
            }
        }
        .padding()
        .onAppear {
            selectedEntries = Set(entries.map { $0.id })
        }
    }

    private func deleteSelectedPhotos() {
        isDeleting = true
        let toDelete = entries.filter { selectedEntries.contains($0.id) }
        let assetsToDelete = toDelete.map { $0.asset }

        Task {
            await photoManager.hardDeleteAssets(assetsToDelete)

            await MainActor.run {
                isDeleting = false
                deletionComplete = true

                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    dismiss()
                    forceRefresh.toggle()
                }
            }
        }
    }
}
