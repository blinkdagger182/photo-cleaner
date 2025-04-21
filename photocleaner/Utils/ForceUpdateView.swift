//
//  ForceUpdateView.swift
//  photocleaner
//
//  Created by New User on 06/04/2025.
//


import SwiftUI

struct ForceUpdateView: View {
    let notes: String?

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "arrow.down.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .foregroundColor(.blue)

            Text("Update Required")
                .font(.title)
                .bold()

            Text(notes ?? "A new version of this app is required to continue.")
                .multilineTextAlignment(.center)
                .padding()

            Button("Update Now") {
                if let url = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID") {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.white.ignoresSafeArea())
    }
}
