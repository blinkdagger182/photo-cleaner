import SwiftUI

struct ActionBarView: View {
    let onDelete: () -> Void
    let onBookmark: () -> Void
    let onKeep: () -> Void
    
    var body: some View {
        HStack(spacing: 40) {
            CircleButton(icon: "trash", tint: .red) {
                onDelete()
            }
            CircleButton(icon: "bookmark", tint: .yellow) {
                onBookmark()
            }
            CircleButton(icon: "checkmark", tint: .green) {
                onKeep()
            }
        }
        .padding(.bottom, 32)
    }
}

struct CircleButton: View {
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 60, height: 60)
                .background(Circle().strokeBorder(tint, lineWidth: 2))
        }
    }
}

#Preview {
    ActionBarView(
        onDelete: {},
        onBookmark: {},
        onKeep: {}
    )
} 