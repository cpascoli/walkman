import AVKit
import SwiftUI
import UIKit

/// Hosts `AVPlayerViewController` so the native engine gets system transport
/// controls, AirPlay and Picture in Picture.
///
/// Critically for background playback: iOS suspends decoding when a video layer
/// is attached to a backgrounded app, which stops audio too. Detaching the player
/// from the controller on the way to the background keeps audio running, and
/// reattaching on return restores the picture. Picture in Picture is the exception —
/// while it's active the layer must stay attached.
struct VideoSurface: UIViewControllerRepresentable {

    let player: AVPlayer

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        controller.videoGravity = .resizeAspect
        controller.allowsPictureInPicturePlayback = true
        controller.canStartPictureInPictureAutomaticallyFromInline = true
        controller.delegate = context.coordinator

        context.coordinator.attach(controller: controller, player: player)
        return controller
    }

    func updateUIViewController(_ controller: AVPlayerViewController, context: Context) {
        context.coordinator.attach(controller: controller, player: player)
    }

    static func dismantleUIViewController(_ controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.detachObservers()
        controller.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    @MainActor
    final class Coordinator: NSObject, AVPlayerViewControllerDelegate {

        private weak var controller: AVPlayerViewController?
        private var player: AVPlayer?
        private var isPictureInPictureActive = false
        private var observers: [NSObjectProtocol] = []

        func attach(controller: AVPlayerViewController, player: AVPlayer) {
            self.controller = controller
            self.player = player
            if controller.player !== player, UIApplication.shared.applicationState != .background {
                controller.player = player
            }
            guard observers.isEmpty else { return }
            observeApplicationState()
        }

        private func observeApplicationState() {
            let center = NotificationCenter.default

            observers.append(center.addObserver(
                forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.detachPlayerForBackground() }
            })

            observers.append(center.addObserver(
                forName: UIApplication.willEnterForegroundNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.reattachPlayer() }
            })
        }

        private func detachPlayerForBackground() {
            guard !isPictureInPictureActive else { return }
            controller?.player = nil
        }

        private func reattachPlayer() {
            guard let player, controller?.player !== player else { return }
            controller?.player = player
        }

        func detachObservers() {
            observers.forEach(NotificationCenter.default.removeObserver)
            observers.removeAll()
        }

        // MARK: - AVPlayerViewControllerDelegate

        nonisolated func playerViewControllerWillStartPictureInPicture(_ controller: AVPlayerViewController) {
            Task { @MainActor in self.isPictureInPictureActive = true }
        }

        nonisolated func playerViewControllerDidStopPictureInPicture(_ controller: AVPlayerViewController) {
            Task { @MainActor in self.isPictureInPictureActive = false }
        }
    }
}
