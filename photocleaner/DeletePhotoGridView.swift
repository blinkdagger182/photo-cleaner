import SwiftUI
import Photos

struct DeletePhotoGridView: View {
    @Binding var entries: [DeletePreviewEntry]
    @Binding var selectedEntries: Set<UUID>

    let columns = [GridItem(.adaptive(minimum: 100))]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
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
}
