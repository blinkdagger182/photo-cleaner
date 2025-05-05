import SwiftUI

@MainActor
class ToastService: ObservableObject {
    @Published var message: String = ""
    @Published var isVisible: Bool = false
    @Published var actionLabel: String? = nil
    @Published var toastType: ToastType = .info
    
    var actionHandler: (() -> Void)? = nil
    var dismissHandler: (() -> Void)? = nil
    
    enum ToastType {
        case error
        case warning
        case info
        case success
        
        var backgroundColor: Color {
            switch self {
            case .error: return Color(UIColor(red: 1.0, green: 0.95, blue: 0.95, alpha: 1.0))
            case .warning: return Color(UIColor(red: 1.0, green: 0.98, blue: 0.9, alpha: 1.0))
            case .info: return Color(UIColor(red: 0.94, green: 0.99, blue: 1.0, alpha: 1.0))
            case .success: return Color(UIColor(red: 0.94, green: 1.0, blue: 0.96, alpha: 1.0))
            }
        }
        
        var iconColor: Color {
            switch self {
            case .error: return .red
            case .warning: return .orange
            case .info: return .blue
            case .success: return .green
            }
        }
        
        var textColor: Color {
            return .black
        }
        
        var icon: String {
            switch self {
            case .error: return "exclamationmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .info: return "info.circle.fill"
            case .success: return "checkmark.circle.fill"
            }
        }
    }

    func show(_ message: String, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil, type: ToastType = .info) {
        self.message = message
        self.actionLabel = action
        self.actionHandler = onAction
        self.dismissHandler = onDismiss
        self.toastType = type
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
    
    // Convenience methods for different toast types
    func showError(_ message: String, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        show(message, action: action, duration: duration, onAction: onAction, onDismiss: onDismiss, type: .error)
    }
    
    func showWarning(_ message: String, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        show(message, action: action, duration: duration, onAction: onAction, onDismiss: onDismiss, type: .warning)
    }
    
    func showInfo(_ message: String, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        show(message, action: action, duration: duration, onAction: onAction, onDismiss: onDismiss, type: .info)
    }
    
    func showSuccess(_ message: String, action: String? = nil, duration: TimeInterval = 3.0, onAction: (() -> Void)? = nil, onDismiss: (() -> Void)? = nil) {
        show(message, action: action, duration: duration, onAction: onAction, onDismiss: onDismiss, type: .success)
    }

    var overlayView: some View {
        Group {
            if isVisible {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: toastType.icon)
                        .font(.system(size: 24))
                        .foregroundColor(toastType.iconColor)
                    
                    Text(message)
                        .foregroundColor(toastType.textColor)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()

                    if let label = actionLabel {
                        Button(action: {
                            self.actionHandler?()
                            self.isVisible = false
                        }) {
                            Text(label)
                                .font(.subheadline.bold())
                                .foregroundColor(toastType.iconColor)
                        }
                    }
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)
                .background(toastType.backgroundColor)
                .cornerRadius(10)
                .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
                .padding(.horizontal, 16)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: isVisible)
        .padding(.bottom, 20)
    }
}
