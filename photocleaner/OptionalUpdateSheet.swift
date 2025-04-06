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

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "sparkles")
                .font(.system(size: 50))

            Text("Update Available")
                .font(.title2)
                .bold()

            Text(notes ?? "There's a newer version available with improvements.")
                .multilineTextAlignment(.center)
                .padding()

            HStack {
                Button("Maybe Later") {
                    onDismiss()
                }

                Button("Update") {
                    if let url = URL(string: "https://apps.apple.com/app/idYOUR_APP_ID") {
                        UIApplication.shared.open(url)
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
    }
}
