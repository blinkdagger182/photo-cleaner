import SwiftUI
import Photos

struct PhotoCardView: View {
    let image: UIImage?
    let swipeLabel: String?
    let swipeLabelColor: Color
    let offset: CGSize
    let isLoading: Bool
    let previousImage: UIImage?
    let onDragChanged: (DragGesture.Value) -> Void
    let onDragEnded: (DragGesture.Value) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let image = image {
                    // We have the image, display it
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.85)
                        .padding()
                        .background(Color.white)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 30, style: .continuous)
                        )
                        .shadow(radius: 8)
                } else if isLoading, let prevImage = previousImage {
                    // If no image is available yet but we have a previous image, show it with overlay
                    Image(uiImage: prevImage)
                        .resizable()
                        .scaledToFit()
                        .frame(width: geometry.size.width * 0.85)
                        .padding()
                        .background(Color.white)
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 30, style: .continuous)
                        )
                        .shadow(radius: 8)
                        .overlay(
                            ZStack {
                                Color.black.opacity(0.2)
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)
                            }
                        )
                } else {
                    // No previous image available, show skeleton with less white
                    RoundedRectangle(cornerRadius: 30)
                        .fill(Color(white: 0.95))
                        .frame(width: geometry.size.width * 0.85)
                        .shadow(radius: 8)
                        .overlay(
                            VStack {
                                ProgressView()
                                    .padding(.bottom, 8)
                                Text("Loading image...")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        )
                        .padding()
                }

                // Overlay label
                if let swipeLabel = swipeLabel {
                    Text(swipeLabel.uppercased())
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(swipeLabelColor)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.8))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(swipeLabelColor, lineWidth: 3)
                                )
                        )
                        .rotationEffect(.degrees(-15))
                        .opacity(1)
                        .offset(
                            x: swipeLabel == "Keep" ? -40 : 40,
                            y: -geometry.size.height / 4
                        )
                        .transition(.opacity.combined(with: .move(edge: .top)))
                        .animation(.easeInOut(duration: 0.2), value: swipeLabel)
                }
            }
            .offset(x: offset.width, y: offset.width / 10)
            .rotationEffect(.degrees(Double(offset.width / 15)), anchor: .bottomTrailing)
            .animation(.interactiveSpring(response: 0.3, dampingFraction: 0.7), value: offset)
            .gesture(
                DragGesture()
                    .onChanged(onDragChanged)
                    .onEnded(onDragEnded)
            )
        }
    }
} 