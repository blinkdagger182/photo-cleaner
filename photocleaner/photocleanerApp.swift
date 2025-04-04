//
//  photocleanerApp.swift
//  photocleaner
//
//  Created by New User on 03/04/2025.
//

import SwiftUI

@main
struct photocleanerApp: App {
    var body: some Scene {
        WindowGroup {
            SplashView() // Shows after launch screen; can load ContentView
        }

        // 🚀 This is your native launch screen
        WindowGroup("Launch Screen", id: "Launch Screen") {
            LaunchScreen()
        }    }
}
