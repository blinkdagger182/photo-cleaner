import SwiftUI

struct MemorySavedModal: View {
    let memorySavedMB: Double
    let totalMemoryMB: Double
    var onClose: () -> Void
    var onRate: () -> Void

    @Environment(\.colorScheme) var colorScheme
    @State private var progressValue: Double = 0
    @State private var showConfetti: Bool = false

    private var formattedMemorySaved: String {
        let value = memorySavedMB < 1.0 ? memorySavedMB * 1000 : memorySavedMB
        let unit = memorySavedMB < 1.0 ? "KB" : "MB"
        return String(format: "%.1f %@", value, unit)
    }

    var body: some View {
        ZStack {
            // Dimmed full screen background
            Color.black.opacity(0.4)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                VStack(spacing: 8) {
                    Text("🎉 Memory Saved!")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.primary)

                    Text("\(formattedMemorySaved) cleaned from your device")
                        .font(.system(size: 18))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 12)

                // Progress bar
                VStack(spacing: 8) {
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.gray.opacity(0.2))
                            .frame(height: 12)

                        RoundedRectangle(cornerRadius: 6)
                            .fill(
                                LinearGradient(
                                    gradient: Gradient(colors: [.blue, .blue.opacity(0.7)]),
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(0, CGFloat(progressValue) * UIScreen.main.bounds.width * 0.7), height: 12)
                    }

                    HStack {
                        Text("Space cleaned")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()

                        Text("\(Int(progressValue * 100))%")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.blue)
                    }
                    .padding(.horizontal, 4)
                }

                Divider().padding(.vertical, 8)

                VStack(spacing: 16) {
                    VStack(spacing: 4) {
                        Text("Enjoying this app?")
                            .font(.headline)
                            .fontWeight(.bold)

                        Text("Help us grow by leaving a quick rating!")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: onRate) {
                        Text("Rate Now")
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.blue)
                            .cornerRadius(14)
                    }

                    Button(action: onClose) {
                        Text("Close")
                            .font(.subheadline)
                            .foregroundColor(.primary.opacity(0.8))
                    }
                    .padding(.top, 8)
                }
                .padding(.top, 8)
            }
            .padding(28)
            .frame(maxWidth: 400)
            .background(colorScheme == .dark ? Color.black : Color.white)
            .cornerRadius(24)
            .shadow(color: Color.black.opacity(0.15), radius: 20, x: 0, y: 5)
            .overlay(
                ConfettiView(isActive: $showConfetti)
                    .allowsHitTesting(false)
            )
            .onAppear {
                // Play the air-whoosh sound when the modal appears
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    SoundManager.shared.playSound(named: "air-whoosh")
                }
                
                showConfetti = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    withAnimation(.easeInOut(duration: 1.0)) {
                        let ratio = memorySavedMB / totalMemoryMB
                        progressValue = min(ratio, 1.0)
                    }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                    showConfetti = false
                }
            }
        }
    }
}

#Preview {
    MemorySavedModal(
        memorySavedMB: 256.0,
        totalMemoryMB: 1024.0,
        onClose: {},
        onRate: {}
    )
}
