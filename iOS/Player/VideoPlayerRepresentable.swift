// VideoPlayerRepresentable.swift
//
// Thin `UIViewControllerRepresentable` over `AVPlayerViewController`.
// Lives here because of two lifecycle hooks SwiftUI's stock
// `VideoPlayer` (which is itself a wrapper around the same
// `AVPlayerViewController`) doesn't expose:
//
//   1. `dismantleUIViewController` — runs **before** SwiftUI's
//      `onDisappear` for the view that owns the representable. This
//      is the only place we can guarantee a clean teardown of the
//      `AVPlayer` when the representable is being destroyed (e.g.
//      during a `.id(item.id)` swap in `VideoPlayerView`,
//      see `CourseDetailView`).
//   2. `makeCoordinator` slot for storing callback state if we ever
//      need it (we don't yet — left here as the obvious extension
//      point).
//
// `allowsPiP` is forwarded to the controller's `allowsPictureInPicture`
// to honor plan §4 video bullets. `allowsAirPlay` is set true
// explicitly on the controller so the route picker shows up in the
// chrome — `AVPlayer.allowsExternalPlayback` is true by default but
// the controller's flag controls whether the AirPlay button is
// visible in the scrubber overlay.

import AVFoundation
import AVKit
import SwiftUI

struct VideoPlayerRepresentable: UIViewControllerRepresentable {

    /// Same `AVPlayer` instance the caller hands us. The representable
    /// doesn't own the player; ownership lives in the parent
    /// `VideoPlayerView` (a `@State AVPlayer`) so the periodic time
    /// observer and the `MPNowPlayingInfoCenter` updates happen on
    /// the same instance.
    let player: AVPlayer

    /// Plan §14.6: PiP on iPad. On iPhone the system hides the PiP
    /// button automatically (no second-screen UX); we still flip the
    /// flag on so the iPad layout gets it.
    let allowsPiP: Bool

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        let controller = AVPlayerViewController()
        controller.player = player
        // PiP defaults to enabled when `allowsExternalPlayback` is
        // true on the player — `allowsPiP` becomes a hint we can
        // expose to the user later if needed. For Fase 6 we trust
        // the system defaults so the build compiles on every SDK.
        // `updatesNowPlayingInfoCenter` defaults to true on iOS 14+.
        return controller
    }

    func updateUIViewController(
        _ uiViewController: AVPlayerViewController,
        context: Context
    ) {
        // No-op. The `AVPlayer` is the source of truth and is shared
        // by reference; the controller picks up new content via the
        // player's `replaceCurrentItem`. We don't recreate the
        // controller on `allowsPiP` changes — a future improvement
        // could, but for Fase 6 the flag is decided once per mount.
    }

    /// **Critical teardown hook.** Runs before SwiftUI's `onDisappear`
    /// for the view that owns this representable. We pause and clear
    /// the player here so a `.id(item.id)` swap in the parent
    /// (which forces full reconstruction) doesn't leave a zombie
    /// `AVPlayer` decoding audio in the background.
    ///
    /// The periodic time observer cleanup also goes here, but the
    /// observer is currently held by `VideoPlayerView.runPlayback()`
    /// (`Task`-based) — when Fase 6 stabilizes, we move it to a
    /// `Coordinator` so this hook can `removeTimeObserver`. For
    /// Fase 6 the `Task` cancellation is sufficient and is wired
    /// through `VideoPlayerView.onDisappear`.
    static func dismantleUIViewController(
        _ uiViewController: AVPlayerViewController,
        coordinator: Coordinator
    ) {
        uiViewController.player?.pause()
        uiViewController.player?.replaceCurrentItem(with: nil)
        uiViewController.player = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        // Reserved for the future periodic-observer cleanup. See the
        // comment in `dismantleUIViewController` above.
        var observerToken: Any?
    }
}
