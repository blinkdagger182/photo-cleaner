import SwiftUI

enum ToastType {
    case success
    case error
    case info
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        }
    }
}

@MainActor
class ToastService: ObservableObject {
    @Published var message: String = ""
    @Published var isVisible: Bool = false
    @Published var actionLabel: String? = nil
    @Published var type: ToastType = .info
    var actionHandler: (() -> Void)? = nil
    
    static let shared = ToastService()
    
    private init() {}

    func show(message: String, type: ToastType = .info, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil) {
        self.message = message
        self.type = type
        self.actionLabel = action
        self.actionHandler = onAction
        self.isVisible = true

        // Auto-dismiss after `duration`
        Task {
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if isVisible { isVisible = false }
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
                .background(type.color.opacity(0.85))
                .cornerRadius(10)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isVisible)
        .padding(.bottom, 60)
    }
} 