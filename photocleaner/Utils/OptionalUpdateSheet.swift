//
//  OptionalUpdateSheet.swift
//  photocleaner
//
//  Created by New User on 06/04/2025.
//


import SwiftUI

struct OptionalUpdateSheet: View {
    let notes: String?
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @State private var isAnimating = false

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 60))
                .foregroundStyle(
                    colorScheme == .dark ? Color.white : Color.black,
                    colorScheme == .dark ? Color.white.opacity(0.7) : Color.black.opacity(0.7)
                )
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(
                    Animation.easeInOut(duration: 1.5)
                        .repeatForever(autoreverses: true),
                    value: isAnimating
                )
                .onAppear {
                    isAnimating = true
                }

            Text("Update Available")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(Color.primary)

            Text(notes ?? "There's a newer version available with improvements.")
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Color.secondary)
                .padding(.horizontal)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 20) {
                Button("Maybe Later") {
                    onDismiss()
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(colorScheme == .dark ? Color.white : Color.black, lineWidth: 1.5)
                )
                .foregroundStyle(Color.primary)

                Button("Update") {
                    if let url = URL(string: "https://apps.apple.com/my/app/cln-swipe-to-clean/id6744550725") {
                        UIApplication.shared.open(url)
                    }
                }
                .font(.system(size: 16, weight: .medium, design: .rounded))
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(colorScheme == .dark ? Color.white : Color.black)
                )
                .foregroundStyle(colorScheme == .dark ? Color.black : Color.white)
            }
            .padding(.top, 8)
        }
        .padding(30)
    }
}

#Preview {
    OptionalUpdateSheet(notes: "Check out our latest features and improvements!", onDismiss: {})
}
