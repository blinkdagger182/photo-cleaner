import SwiftUI

struct SwipeLimitView: View {
    let swipesUsed: Int
    let dailyLimit: Int
    var onUpgradePressed: (() -> Void)? = nil
    
    private var progress: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(1.0, Double(swipesUsed) / Double(dailyLimit))
    }
    
    var body: some View {
        HStack(spacing: 12) {
            // Left side: Progress and count
            VStack(alignment: .leading, spacing: 4) {
                // Swipe count label
                HStack(spacing: 4) {
                    Text("\(swipesUsed) / \(dailyLimit)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                    
                    Text("swipes today")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if swipesUsed >= dailyLimit {
                        HStack(spacing: 2) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 9))
                            Text("Limit")
                        }
                        .font(.caption2)
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red.opacity(0.9))
                        .cornerRadius(4)
                    }
                }
                
                // Progress bar with GeometryReader for accurate width
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        // Background track
                        Rectangle()
                            .fill(Color(.systemGray5))
                            .frame(height: 6)
                            .cornerRadius(3)
                        
                        // Progress
                        Rectangle()
                            .fill(progressColor)
                            .frame(width: progress * geometry.size.width, height: 6)
                            .cornerRadius(3)
                    }
                }
                .frame(height: 6)
            }
            
            // Right side: Upgrade button
            Button(action: {
                onUpgradePressed?()
            }) {
                Text("Upgrade")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.accentColor)
                    .cornerRadius(12)
            }
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 2)
        )
        .padding(.horizontal, 16)
    }
    
    private var progressColor: Color {
        if progress >= 0.9 {
            return .red
        } else if progress >= 0.7 {
            return .orange
        } else {
            return .blue
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        SwipeLimitView(swipesUsed: 2, dailyLimit: 5)
        SwipeLimitView(swipesUsed: 5, dailyLimit: 5)
    }
    .padding()
    .background(Color(.systemGroupedBackground))
} 
