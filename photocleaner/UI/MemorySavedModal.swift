import SwiftUI
import StoreKit

struct MemorySavedModal: View {
    // MARK: - Properties
    @Binding var isShowing: Bool
    let memorySavedMB: Double
    let totalMemoryMB: Double
    var onClose: (() -> Void)?
    var onRate: (() -> Void)?
    
    // MARK: - Initialization
    init(isShowing: Binding<Bool>, memorySavedMB: Double, totalMemoryMB: Double) {
        self._isShowing = isShowing
        self.memorySavedMB = memorySavedMB
        self.totalMemoryMB = totalMemoryMB
    }
    
    // Legacy initializer for backward compatibility
    init(memorySavedMB: Double, totalMemoryMB: Double, onClose: (() -> Void)? = nil, onRate: (() -> Void)? = nil) {
        self._isShowing = .constant(true)
        self.memorySavedMB = memorySavedMB
        self.totalMemoryMB = totalMemoryMB
        self.onClose = onClose
        self.onRate = onRate
    }
    
    // MARK: - Body
    var body: some View {
        VStack(spacing: 24) {
            // Header with icon
            VStack(spacing: 16) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(.green)
                
                Text("Memory Saved!")
                    .font(.title)
                    .fontWeight(.bold)
                    .multilineTextAlignment(.center)
            }
            
            // Memory saved details
            VStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "externaldrive.fill")
                        .foregroundColor(.blue)
                    
                    Text("You saved \(String(format: "%.1f", memorySavedMB)) MB")
                        .font(.headline)
                }
                
                HStack(spacing: 8) {
                    Image(systemName: "chart.bar.fill")
                        .foregroundColor(.purple)
                    
                    Text("Total saved: \(String(format: "%.1f", totalMemoryMB)) MB")
                        .font(.subheadline)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 16)
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Action buttons
            VStack(spacing: 12) {
                Button(action: {
                    if let onRate = onRate {
                        onRate()
                    } else {
                        requestAppReview()
                        isShowing = false
                    }
                }) {
                    HStack {
                        Image(systemName: "star.fill")
                            .foregroundColor(.white)
                        Text("Rate the App")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .cornerRadius(12)
                }
                
                Button(action: {
                    if let onClose = onClose {
                        onClose()
                    } else {
                        isShowing = false
                    }
                }) {
                    Text("Continue")
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray5))
                        .cornerRadius(12)
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 24)
                .fill(Color(.systemBackground))
                .shadow(radius: 20)
        )
        .padding(24)
    }
    
    // Function to request app review
    private func requestAppReview() {
        // Check if we're on a physical device (StoreKit review prompts don't work in simulators)
        #if !targetEnvironment(simulator)
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            print("No window scene found, skipping review request")
            return
        }
        
        // Request the review
        if #available(iOS 14.0, *) {
            SKStoreReviewController.requestReview(in: windowScene)
        } else {
            // Fallback on earlier versions
            SKStoreReviewController.requestReview()
        }
        #endif
    }
}

// MARK: - Preview
#Preview {
    ZStack {
        Color.gray.opacity(0.3).ignoresSafeArea()
        
        MemorySavedModal(
            isShowing: .constant(true),
            memorySavedMB: 125.3,
            totalMemoryMB: 1024.5
        )
    }
}
