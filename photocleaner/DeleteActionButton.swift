import SwiftUI
struct DeleteActionButton: View {
    var isProcessing: Bool
    var isCompleted: Bool
    var onDelete: () -> Void

    var body: some View {
        if isCompleted {
            Label("Deleted", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundColor(.green)
        } else if isProcessing {
            ProgressView("Deleting…")
                .progressViewStyle(CircularProgressViewStyle())
        } else {
            Button(action: onDelete) {
                Text("Delete")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.red)
                    .foregroundColor(.white)
                    .cornerRadius(12)
            }
        }
    }
}
