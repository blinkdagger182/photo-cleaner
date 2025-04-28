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
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(red: 0.15, green: 0.08, blue: 0.4))
                    .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
            )
            .padding(.horizontal, 16)
            }
            .buttonStyle(ScaleButtonStyle())
            
            // Dismiss button
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.white.opacity(0.7))
                    .background(Color.clear)
            }
            .padding(12)
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
