import SwiftUI

struct MarketingBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {

            Button(action: onTap) {
                HStack(spacing: 16) {
                // Logo/Icon section
                Image("smartalbums_image")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                
                // Text content
                VStack(alignment: .leading, spacing: 2) {
                    Text("CLN. Discover")
                        .font(.headline)
                        .foregroundColor(.yellow)
                    
                    Text("Your memories, magically sorted. Just one tap away.")
                        .font(.subheadline)
                        .foregroundColor(.white)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // CTA Button
                Text("Get started")
                    .font(.callout)
                    .fontWeight(.medium)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.mint)
                    .foregroundColor(.black)
                    .cornerRadius(16)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                Image("gradient-background")
                .resizable()
                .scaledToFill()
                .ignoresSafeArea()
                .frame(maxWidth: .infinity, maxHeight: 70)
                .clipShape(RoundedRectangle(cornerRadius: 16))
                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 16)
            }
            .buttonStyle(ScaleButtonStyle())
        }
    }
}

// Scale animation for the button
//private struct ScaleButtonStyle: ButtonStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        configuration.label
//            .scaleEffect(configuration.isPressed ? 0.97 : 1)
//            .animation(.easeInOut(duration: 0.2), value: configuration.isPressed)
//    }
//}

#Preview {
    VStack {
        Spacer()
        MarketingBanner {
            print("Banner tapped")
        } onDismiss: {
            print("Banner dismissed")
        }
        Spacer()
    }
    .background(Color.gray.opacity(0.2))
}

struct PremiumAlertBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void
    @Binding var showPaywall: Bool

    var body: some View {
        VStack(spacing: 12) {
            Image("premium_alert_banner") // Add the image to Assets
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: .infinity)

            Button(action: {
                onDismiss() // First dismiss the banner
                onTap() // Then go to discover tab
                showPaywall = true // Show the paywall
            }) {
                Text("Unlock cln+")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.mint)
                    .foregroundColor(.black)
                    .cornerRadius(20)
            }

            Button(action: onDismiss) {
                Text("Maybe later")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
            }
        }
        .background(Color.white.opacity(0.9))
        .cornerRadius(24)
        .padding()
        .shadow(radius: 8)
    }
}
