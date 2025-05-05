import SwiftUI

struct MarketingBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Main banner content
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
                        .frame(maxWidth: .infinity, maxHeight: 70)
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                        .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                )
            }
            .contentShape(RoundedRectangle(cornerRadius: 16))
            .buttonStyle(ScaleButtonStyle())
        }
        .padding(.horizontal, 16)
    }
}

// Scale animation for the button


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

// struct PremiumAlertBanner: View {
//     var onTap: () -> Void
//     var onDismiss: () -> Void
//     @Binding var showPaywall: Bool

//     var body: some View {
//         VStack(spacing: 12) {
//             Image("premium_alert_banner") // Add the image to Assets
//                 .resizable()
//                 .aspectRatio(contentMode: .fit)
//                 .frame(maxWidth: .infinity)

//             Button(action: {
//                 onDismiss() // First dismiss the banner
//                 onTap() // Then go to discover tab
//             }) {
//                 Text("View Collections")
//                     .font(.headline)
//                     .padding(.horizontal, 24)
//                     .padding(.vertical, 14)
//                     .background(Color.mint)
//                     .foregroundColor(.black)
//                     .cornerRadius(20)
//             }

//             Button(action: onDismiss) {
//                 Text("Maybe later")
//                     .font(.footnote)
//                     .foregroundColor(.gray)
//                     .padding(.bottom, 4)
//             }
//         }
//         .background(Color.white.opacity(0.9))
//         .cornerRadius(24)
//         .padding()
//         .shadow(radius: 8)
//     }
// }

struct PremiumAlertBanner: View {
    var onTap: () -> Void
    var onDismiss: () -> Void
    @Binding var showPaywall: Bool

    @State private var offset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    // Thresholds
    private let dismissThreshold: CGFloat = 150
    private let velocityThreshold: CGFloat = 1000

    var body: some View {
        VStack(spacing: 12) {
            Image("premium_alert_banner")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 280) // Smaller width

            Button(action: {
                onDismiss()
                onTap()
            }) {
                Text("View Collections")
                    .font(.headline)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 14)
                    .background(Color.mint)
                    .foregroundColor(.black)
                    .cornerRadius(20)
            }

            Button(action: onDismiss) {
                Text("Swipe To Dismiss")
                    .font(.footnote)
                    .foregroundColor(.gray)
                    .padding(.bottom, 4)
            }
        }
        .background(Color.white.opacity(0.9))
        .cornerRadius(24)
        .padding()
        .shadow(radius: 8)
        .offset(x: offset.width + dragOffset.width, y: offset.height + dragOffset.height)
        .gesture(
            DragGesture()
                .updating($dragOffset) { value, state, _ in
                    state = value.translation
                }
                .onEnded { value in
                    let totalOffset = CGSize(
                        width: offset.width + value.translation.width,
                        height: offset.height + value.translation.height
                    )

                    let velocity = sqrt(pow(value.predictedEndTranslation.width, 2) + pow(value.predictedEndTranslation.height, 2))

                    if abs(totalOffset.width) > dismissThreshold || abs(totalOffset.height) > dismissThreshold || velocity > velocityThreshold {
                        withAnimation(.easeOut(duration: 0.3)) {
                            offset = CGSize(
                                width: value.translation.width > 0 ? 1000 : -1000,
                                height: value.translation.height > 0 ? 1000 : -1000
                            )
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            onDismiss()
                        }
                    } else {
                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                            offset = .zero
                        }
                    }
                }
        )
        .animation(.spring(response: 0.4, dampingFraction: 0.75), value: dragOffset)
    }
}
