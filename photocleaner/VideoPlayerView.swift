//
//  VideoPlayerView.swift
//  photocleaner
//
//  Created by New User on 06/04/2025.
//


import SwiftUI
import AVKit

struct VideoPlayerView: UIViewControllerRepresentable {
    @Binding var fadeIn: Bool
    @Binding var fadeOut: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.showsPlaybackControls = false
        controller.videoGravity = AVLayerVideoGravity.resizeAspect

        if let asset = NSDataAsset(name: "ClnVideo") {
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("ClnVideo.mp4")
            try? asset.data.write(to: tempURL)

            let playerItem = AVPlayerItem(url: tempURL)
            let queuePlayer = AVQueuePlayer()
            let looper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem)

            controller.player = queuePlayer
            queuePlayer.isMuted = true
            queuePlayer.play()

            context.coordinator.looper = looper
        }

        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        uiViewController.view.alpha = fadeOut ? 0 : 1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator {
        var looper: AVPlayerLooper?
    }
}
