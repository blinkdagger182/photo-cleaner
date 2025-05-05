import SwiftUI

struct DiscoverPromoBanner: View {
    var onTap: () -> Void
    
    // Current discount percentage
    private let discountPercentage = 36
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 12) {
                // Top section with main headline
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Unlock Unlimited Daily Swipes")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(.white)
                        
                        Text("You've tried it, now love it! Remove daily limits forever.")
                            .font(.system(size: 14))
                            .foregroundColor(.white.opacity(0.8))
                    }
                    
                    Spacer()
                    
                    // Discount badge
                    Text("Save \(discountPercentage)%")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                }
                
                // CTA Button
                HStack {
                    Spacer()
                    
                    Text("Upgrade to Premium")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.black)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 20)
                        .background(
                            Capsule()
                                .fill(Color.white)
                        )
                    
                    Spacer()
                }
            }
            .padding(16)
            .background(
                LinearGradient(
                    gradient: Gradient(colors: [
                        Color(red: 0.53, green: 0.42, blue: 0.95), // Purple
                        Color(red: 0.36, green: 0.7, blue: 0.93)   // Blue
                    ]),
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(.horizontal, 16)
    }
}

#if DEBUG
struct DiscoverPromoBanner_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.opacity(0.2).edgesIgnoringSafeArea(.all)
            
            DiscoverPromoBanner {
                print("Banner tapped")
            }
        }
    }
}
#endif 