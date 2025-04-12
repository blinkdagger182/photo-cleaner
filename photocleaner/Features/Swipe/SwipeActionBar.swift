import SwiftUI

struct SwipeActionBar: View {
    let onDelete: () -> Void
    let onBookmark: () -> Void
    let onKeep: () -> Void
    
    var body: some View {
        HStack(spacing: 24) {
            Button(action: onDelete) {
                VStack {
                    Image(systemName: "trash")
                        .font(.system(size: 24))
                        .foregroundColor(.red)
                        .frame(width: 60, height: 60)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                    
                    Text("Delete")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            
            Button(action: onBookmark) {
                VStack {
                    Image(systemName: "bookmark")
                        .font(.system(size: 24))
                        .foregroundColor(.blue)
                        .frame(width: 60, height: 60)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                    
                    Text("Save")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
            
            Button(action: onKeep) {
                VStack {
                    Image(systemName: "checkmark")
                        .font(.system(size: 24))
                        .foregroundColor(.green)
                        .frame(width: 60, height: 60)
                        .background(Color.white)
                        .clipShape(Circle())
                        .shadow(radius: 3)
                    
                    Text("Keep")
                        .font(.caption)
                        .foregroundColor(.primary)
                }
            }
        }
        .padding(.vertical, 20)
    }
} 