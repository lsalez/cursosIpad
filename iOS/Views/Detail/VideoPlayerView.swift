// VideoPlayerView.swift
//
// The "lesson view" — replaces `CourseDetailView` entirely when a
// video lesson is selected. Push on iPhone, split iPad layout when
// the host environment is `.regular` horizontal size class.
//
// Architectural notes worth keeping in mind:
//
//   * **`.id(item.id)` is applied by the parent** (`CourseDetailView`),
//     not here. The view itself has no way to detect its own identity
//     change. The parent's `.id(...)` forces full reconstruction on
//     every lesson swap, which makes the `dismantleUIViewController`
//     hook in `VideoPlayerRepresentable` the canonical place to clean
//     up the `AVPlayer`.
//
//   * **Resume-seek race protection.** Arming a 5-second writer before
//     the initial seek has completed writes `positionSeconds: 0` to
//     disk, clobbering the persisted resume point. The fix is two
//     `@State` gates — `didIssueInitialSeek` and
//     `didReceiveFirstContentTime` — that must both be true before
//     any periodic writer fires. See `periodicTick(...)`.
//
//   * **Single periodic observer** at 1Hz drives everything: the
//     5-second flush, the `MPNowPlayingInfoCenter` updates, the 95%
//     toast, and the failure-detection branch. The closure runs on
//     `.main`, so it's safe to mutate `@State` from inside.
//
//   * **Search position consumption** goes through `onPositionConsumed`
//     so the parent (`CourseDetailView`) can clear its local
//     `pendingPosition` and the store-level intent. Fires exactly
//     once per lesson (after the seek issued).

import AVFoundation
import MediaPlayer
import Shared
import SwiftUI

struct VideoPlayerView: View {

    // MARK: - Inputs

    let course: Course
    let item: CourseItem

    /// Seconds to seek to once the player's item is ready. `nil`
    /// means "start at zero"; non-nil means "this is a resume or a
    /// search-result jump". AVPlayer buffers the seek before the
    /// item reaches `.readyToPlay`, so we issue it eagerly and don't
    /// have to wait.
    let initialStartSeconds: Double?

    /// Back / dismiss — wired to `selectedLesson = nil` in the
    /// parent.
    let onDismiss: () -> Void

    /// Tap on a lesson in the right-side curriculum (iPad split).
    let onSelectLesson: (CourseItem) -> Void

    /// Fires exactly once per lesson when the initial seek is
    /// issued. The parent uses this to clear its own
    /// `pendingPosition` and the store-level intent.
    let onPositionConsumed: () -> Void

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var library: LibraryStore

    // MARK: - Mutable state

    /// The single `AVPlayer` instance for this lesson. Held across
    /// re-renders of the same lesson via `@State`; recreated when
    /// `.id(item.id)` triggers in the parent.
    @State private var player: AVPlayer = AVPlayer()

    /// Two flags gating the periodic writer. Both must be true
    /// before the 5-second flush fires.
    @State private var didIssueInitialSeek = false
    @State private var didReceiveFirstContentTime = false

    /// True once we've told the parent the initial seek fired. Used
    /// to avoid a duplicate `onPositionConsumed` if the periodic
    /// observer's first tick arrives after the seek but before the
    /// resume-race window closes.
    @State private var didCallOnPositionConsumed = false

    /// Toast control. See `periodicTick` for the 95% gate.
    @State private var showCompletionToast = false
    @State private var toastFiredForThisItem = false

    /// Set when the video can't be opened (file deleted, decode
    /// failed, etc.) — replaces the chrome with an error message.
    @State private var loadError: String?

    /// Periodic-time-observer token. Held on `@State` so the
    /// reference doesn't get dropped between body renders. Cleared
    /// in `tearDownPlayback` via `removeTimeObserver`.
    @State private var observerToken: Any?

    // MARK: - Body

    var body: some View {
        Group {
            if let loadError {
                errorChrome(message: loadError)
            } else if sizeClass == .regular {
                iPadSplit
            } else {
                iPhoneStack
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationBarBackButtonHidden(true)
        .task { await runPlayback() }
        .onDisappear {
            tearDownPlayback()
        }
    }

    // MARK: - iPad split

    private var iPadSplit: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                Divider().background(Color.appDivider)
                playerArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(idealWidth: 460, maxWidth: 620)
            .background(Color.black.opacity(0.04))

            Divider().background(Color.appDivider)

            CurriculumView(
                course: course,
                accent: Color.themeAdjusted(from: accentColor),
                highlightedItemID: item.id,
                courseDirectory: library.courseDirectoryURL(for: course),
                onTapLesson: onSelectLesson
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - iPhone stack

    private var iPhoneStack: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(Color.appDivider)
            playerArea
            Divider().background(Color.appDivider)
            iPhoneInfoTabs
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.appBackground)
        }
    }

    // MARK: - Top bar (shared)

    private var topBar: some View {
        HStack(spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.backward")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appTitle)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.appMenu.opacity(0.08)))
            }
            .accessibilityLabel("Volver al curso")
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appTitle)
                    .lineLimit(1)
                Text(course.title)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInfo)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                library.markItemCompleted(
                    courseID: course.id,
                    itemRelativePath: item.relativePath
                )
            } label: {
                Label(
                    item.progress.isCompleted ? "Visto" : "Marcar como visto",
                    systemImage: item.progress.isCompleted
                        ? "checkmark.circle.fill"
                        : "checkmark.circle"
                )
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    item.progress.isCompleted
                        ? Color.appAccentFallback
                        : accentColor
                )
            }
            .buttonStyle(.plain)
            .disabled(item.progress.isCompleted)
            .accessibilityHint("Marca esta lección como vista.")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.appBackground)
    }

    // MARK: - Player area

    private var playerArea: some View {
        ZStack {
            Color.black
            VideoPlayerRepresentable(
                player: player,
                allowsPiP: sizeClass == .regular
            )
            if showCompletionToast {
                completionToast
            }
        }
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .frame(maxWidth: .infinity)
    }

    private var completionToast: some View {
        VStack {
            HStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.white)
                Text("¿Marcar como completado?")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer(minLength: 8)
                Button("Sí") {
                    library.markItemCompleted(
                        courseID: course.id,
                        itemRelativePath: item.relativePath
                    )
                    showCompletionToast = false
                }
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Capsule().fill(.white.opacity(0.25)))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.black.opacity(0.75))
            )
            .padding(.horizontal, 12)
            .padding(.top, 12)
            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    // MARK: - iPhone info tabs

    private var iPhoneInfoTabs: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Acerca de")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appTitle)
            Text(descriptionText)
                .font(.system(size: 13))
                .foregroundStyle(Color.appInfo)
            Text("Recursos")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appTitle)
                .padding(.top, 6)
            Text(item.relativePath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.appInfo)
            Spacer()
        }
        .padding(16)
    }

    /// Stub for Fase 6: returns "Sin descripción" until Fase 10 wires
    /// the Mac editor's `description` field into the sidecar.
    private var descriptionText: String {
        "Sin descripción."
    }

    // MARK: - Error chrome

    private func errorChrome(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("No se pudo abrir esta lección")
                .font(.headline)
                .foregroundStyle(Color.appTitle)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button("Volver al curso", action: onDismiss)
                .buttonStyle(.borderedProminent)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }

    // MARK: - Helpers

    /// Per plan §2 #11: accent is the cover-derived dynamic color
    /// adjusted per theme. The `library` environment provides it.
    private var accentColor: Color {
        library.coverColor(for: course)
    }

    // MARK: - Playback lifecycle

    /// Top-level playback driver. Called from `.task` — its
    /// cancellation propagates to the periodic-time-observer cleanup
    /// through `tearDownPlayback` (triggered by `.onDisappear`).
    ///
    /// Order of operations is deliberate:
    /// 1. Resolve the file URL. Fail loud with `loadError` if missing.
    /// 2. Build the `AVPlayerItem` and replace the player's current.
    /// 3. Issue the initial seek (`initialStartSeconds`). AVPlayer
    ///    buffers pre-ready seeks, so we don't have to wait for
    ///    `.readyToPlay` to fire.
    /// 4. Notify the parent (`onPositionConsumed`) so its banner
    ///    clears. The notification is gated on `initialStartSeconds`
    ///    being non-nil because the resume-race gates already cover
    ///    the open-from-zero case.
    /// 5. Register the periodic time observer at 1Hz. Closure runs
    ///    on `.main`, so it's safe to mutate `@State` from inside.
    /// 6. Park the task until cancelled. When `.task` cancels, the
    ///    surrounding flow returns and `tearDownPlayback` runs from
    ///    `.onDisappear`.
    private func runPlayback() async {
        guard let url = library.itemURL(for: course, item: item) else {
            loadError = "Archivo no encontrado."
            return
        }

        // Build the AVPlayerItem. AVPlayer buffers it for us.
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        player.replaceCurrentItem(with: playerItem)

        // Issue the initial seek. AVPlayer accepts pre-ready seeks and
        // applies them as soon as the item reports readyToPlay.
        // The async variant queues internally when the item isn't
        // ready yet — equivalent to AVPlayer's pre-iOS-16 sync seek
        // in behavior, just expressed via `await` for the modern
        // API.
        if let initial = initialStartSeconds, initial > 0 {
            let target = CMTime(seconds: initial, preferredTimescale: 600)
            await player.seek(
                to: target,
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }
        didIssueInitialSeek = true

        // Notify the parent *after* setting `didIssueInitialSeek` so
        // any downstream state read inside the callback is consistent
        // with the gates the periodic writer also reads.
        if !didCallOnPositionConsumed, initialStartSeconds != nil {
            didCallOnPositionConsumed = true
            onPositionConsumed()
        }

        // Register the periodic observer. 1Hz is plenty for the 5s
        // checkpoint and avoids burning CPU on a `.1`s cadence when
        // the player is paused.
        let interval = CMTime(seconds: 1, preferredTimescale: 600)
        let token = player.addPeriodicTimeObserver(
            forInterval: interval,
            queue: .main
        ) { [self] time in
            periodicTick(at: time)
        }
        observerToken = token

        // Park here until cancelled. `.task` cancels us when the
        // view unmounts. Observer removal is in `tearDownPlayback`.
        await waitForever()

        // Defensive: if cancellation propagates to here before
        // `.onDisappear` runs (rare but possible), make sure the
        // observer is gone too.
        if let observerToken {
            player.removeTimeObserver(observerToken)
            self.observerToken = nil
        }
    }

    /// `Task.never`-style await; sits here until `.task`'s
    /// cancellation propagates.
    private func waitForever() async {
        try? await Task.sleep(nanoseconds: .max)
    }

    /// Single callback point for everything that needs to react to
    /// every-second player ticks. Decides whether to flush, update
    /// Control Center, fire the 95% toast, or surface an error.
    private func periodicTick(at time: CMTime) {
        let seconds = CMTimeGetSeconds(time)
        guard seconds.isFinite, seconds >= 0 else { return }

        // Open the "first non-zero time" gate as soon as we see real
        // frame data.
        if !didReceiveFirstContentTime, seconds > 0.5 {
            didReceiveFirstContentTime = true
        }

        // Flush every 5s AND on pause — both gated on the resume race
        // being closed.
        if didIssueInitialSeek && didReceiveFirstContentTime {
            let wholeSeconds = Int(seconds)
            if wholeSeconds > 0, wholeSeconds % 5 == 0 {
                writePosition(seconds: seconds)
            }
            if player.timeControlStatus == .paused {
                writePosition(seconds: seconds)
            }
        }

        // MPNowPlayingInfoCenter pill.
        updateNowPlayingInfo(seconds: seconds)

        // 95% toast gate. Fires at most once per lesson — the
        // `.id(item.id)` swap in the parent resets the view state.
        if !toastFiredForThisItem,
           let duration = item.durationSeconds,
           duration > 0,
           seconds > duration * 0.95
        {
            toastFiredForThisItem = true
            withAnimation { showCompletionToast = true }
        }

        // Failure detection.
        if let status = player.currentItem?.status, status == .failed {
            loadError = "No se pudo reproducir el video."
        }
    }

    /// Single funnel for the sidecar write. Off-main so we don't
    /// block disk I/O on the UI thread; serialized through the
    /// `SidecarWriter` actor (Fase 5).
    private func writePosition(seconds: Double) {
        let path = item.relativePath
        let courseID = course.id
        Task { @MainActor in
            library.updateItemProgress(
                courseID: courseID,
                itemRelativePath: path,
                positionSeconds: seconds,
                lastViewedAt: Date()
            )
        }
    }

    /// Fire-and-forget `MPNowPlayingInfoCenter` update. Cheap dict
    /// allocation; no need to dedupe.
    private func updateNowPlayingInfo(seconds: Double) {
        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.title
        info[MPMediaItemPropertyArtist] = course.title
        if let duration = item.durationSeconds {
            info[MPMediaItemPropertyPlaybackDuration] = duration
        }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = seconds
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.rate
        if let coverURL = library.coverURL(for: course),
           let image = UIImage(contentsOfFile: coverURL.path),
           let data = image.jpegData(compressionQuality: 0.7),
           let reencoded = UIImage(data: data)
        {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in reencoded }
            info[MPMediaItemPropertyArtwork] = artwork
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }

    /// Final flush on tear-down. Runs from `.onDisappear`. The
    /// `dismantleUIViewController` in `VideoPlayerRepresentable` is
    /// what actually clears the underlying AVPlayer; this method
    /// clears app-level state (now playing, observer token).
    private func tearDownPlayback() {
        if let observerToken {
            player.removeTimeObserver(observerToken)
            self.observerToken = nil
        }
        player.pause()
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}
