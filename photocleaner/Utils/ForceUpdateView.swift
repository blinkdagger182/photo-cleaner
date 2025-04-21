//
//  ForceUpdateOverlayView.swift
//  photocleaner
//
//  Created by New User on 06/04/2025.
//

import SwiftUI

struct ForceUpdateView: View {
    let notes: String?
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false
    
    var body: some View {
        ZStack {
            Color(UIColor.systemBackground)
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                // Custom CLN-style logo
                ZStack {
                    // Outer circle
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [.purple, .blue],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 110, height: 110)
                    
                    // Inner circle
                    Circle()
                        .fill(colorScheme == .dark ? Color.black : Color.white)
                        .frame(width: 70, height: 70)
                    
                    // Download arrow
                    Image(systemName: "arrow.down")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(
                            LinearGradient(
                                colors: [.green, .blue],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                }
                .shadow(color: Color.purple.opacity(0.5), radius: 10, x: 0, y: 5)
                .scaleEffect(isAnimating ? 1.1 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.2)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
                .onAppear {
                    isAnimating = true
                }
                
                VStack(spacing: 16) {
                    Text("Time to Update")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.primary)
                    
                    Text(notes ?? "We've made this app even better! Please update to continue enjoying all the features.")
                        .font(.system(size: 17, weight: .regular, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Color.secondary)
                        .padding(.horizontal)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                Spacer().frame(height: 12)
                
                Button {
                    if let url = URL(string: "https://apps.apple.com/my/app/cln-swipe-to-clean/id6744550725") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    HStack {
                        Image(systemName: "arrow.up.circle.fill")
                        Text("Update Now")
                            .fontWeight(.semibold)
                    }
                    .frame(minWidth: 200, minHeight: 54)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                }
                .buttonStyle(MonochromeButtonStyle())
                .controlSize(.large)
                .shadow(color: colorScheme == .dark ? Color.white.opacity(0.2) : Color.black.opacity(0.2), radius: 5, x: 0, y: 3)
                
                Text("Update takes just a moment")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color.secondary.opacity(0.8))
                    .padding(.top, 8)
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 40)
        }
    }
}

struct MonochromeButtonStyle: ButtonStyle {
    @Environment(\.colorScheme) private var colorScheme
    
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(colorScheme == .dark ? Color.white : Color.black)
            )
            .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
    }
}

#Preview {
    ForceUpdateView(notes: nil)
}
