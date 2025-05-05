import SwiftUI

struct SwipeLimitView: View {
    let swipesUsed: Int
    let dailyLimit: Int
    
    private var progress: Double {
        guard dailyLimit > 0 else { return 0 }
        return min(1.0, Double(swipesUsed) / Double(dailyLimit))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Swipe count label
            HStack {
                Text("\(swipesUsed) / \(dailyLimit) swipes used today")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                if swipesUsed >= dailyLimit {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.fill")
                            .font(.system(size: 10))
                        Text("Limit reached")
                    }
                    .font(.caption2)
                    .foregroundColor(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.red.opacity(0.15))
                    )
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
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
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