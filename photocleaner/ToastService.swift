import SwiftUI

@MainActor
class ToastService: ObservableObject {
    @Published var message: String = ""
    @Published var isVisible: Bool = false
    @Published var actionLabel: String? = nil
    var actionHandler: (() -> Void)? = nil
    var dismissHandler: (() -> Void)? = nil

    func show(_ message: String, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        self.message = message
        self.actionLabel = action
        self.actionHandler = onAction
        self.dismissHandler = onDismiss
        self.isVisible = true

        // Auto-dismiss after `duration`
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if isVisible {
                self.dismissHandler?()
                isVisible = false
            }
        }
    }

    var overlayView: some View {
        Group {
            if isVisible {
                HStack {
                    Text(message)
                        .foregroundColor(.white)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)

                    Spacer()

                    if let label = actionLabel {
                        Button(action: {
                            self.actionHandler?()
                            self.isVisible = false
                        }) {
                            Text(label)
                                .underline()
                                .font(.subheadline.bold())
                        }
                        .foregroundColor(.white)
                    }
                }
                .padding()
                .background(Color.black.opacity(0.85))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .padding(.bottom, 60)
    }
}
