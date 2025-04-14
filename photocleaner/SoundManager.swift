import Foundation
import AVFoundation
import UIKit

class SoundManager {
    static let shared = SoundManager() // Singleton for easy access
    private var audioPlayer: AVAudioPlayer?

    private init() {} // Private init for singleton

    func playSound(named soundName: String) {
        // For Assets.xcassets datasets, we need to use the correct approach
        if let asset = NSDataAsset(name: soundName) {
            do {
                // Configure audio session for short playback
                try AVAudioSession.sharedInstance().setCategory(.ambient, mode: .default)
                try AVAudioSession.sharedInstance().setActive(true)

                audioPlayer = try AVAudioPlayer(data: asset.data)
                audioPlayer?.prepareToPlay() // Pre-load buffer
                audioPlayer?.play()
                print("🔊 Playing sound: \(soundName)")
            } catch {
                print("Error playing sound \(soundName): \(error.localizedDescription)")
            }
        } else {
            print("Error: Sound file '\(soundName)' not found in assets.")
        }
    }
} 