// MacItemPreview.swift
//
// Right pane of the Mac course editor. Embeds a per-type preview
// for the currently selected `CourseItem`:
//
//   * `.video`  → SwiftUI `VideoPlayer` wrapping an `AVPlayer` +
//                 a "Fijar este frame como miniatura" toolbar.
//                 ⌘F is the keyboard shortcut. Disabled while the
//                 player isn't paused.
//   * `.pdf`    → `PDFView` (PDFKit) via `NSViewRepresentable`.
//   * `.html`   → `WKWebView` (WebKit) via `NSViewRepresentable`,
//                 loaded with `loadFileURL(_:allowingReadAccessTo:)`
//                 so relative links inside the HTML resolve.
//   * `nil`     → empty-state placeholder.
//
// The video preview keeps its own `AVPlayer` so the parent doesn't
// have to manage the player's lifecycle across item swaps —
// `VideoPlayer` re-binds the player each time the `item` argument
// changes (the view is `.id(item.id)`-ed by the parent for that
// exact reason). See `MacCourseEditor.editor(for:)` for the swap.

import AVFoundation
import AVKit
import PDFKit
import Shared
import SwiftUI
import WebKit

struct MacItemPreview: View {
    let item: CourseItem?
    let courseURL: URL
    let onError: (String) -> Void
    let onItemChanged: () -> Void

    var body: some View {
        Group {
            if let item {
                content(for: item)
                    .id(item.id) // Force a full re-instantiation
                                 // when the selection changes so
                                 // AVPlayer / WKWebView rebind.
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }

    @ViewBuilder
    private func content(for item: CourseItem) -> some View {
        let url = courseURL.appendingPathComponent(item.relativePath, isDirectory: false)
        switch item.type {
        case .video:
            VideoPreview(
                videoURL: url,
                courseURL: courseURL,
                onItemChanged: onItemChanged,
                onError: onError
            )
        case .pdf:
            PDFPreview(url: url)
        case .html:
            HTMLPreview(url: url, baseURL: courseURL)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "rectangle.on.rectangle.angled")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Selecciona una lección")
                .font(.title3.bold())
                .foregroundStyle(Color.appTitle)
            Text("Elegí un video, PDF o HTML del árbol de la izquierda para previsualizarlo aquí.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Video preview

private struct VideoPreview: View {
    let videoURL: URL
    let courseURL: URL
    let onItemChanged: () -> Void
    let onError: (String) -> Void

    @State private var player: AVPlayer
    @State private var isExtracting: Bool = false
    /// Polled by a `TimelineView` so the "Fijar este frame" button
    /// can react to play/pause transitions. SwiftUI's
    /// `VideoPlayer` doesn't expose `timeControlStatus` as a
    /// `@Published` value, so we sample it on each render.
    @State private var timeControlStatus: AVPlayer.TimeControlStatus = .paused

    init(
        videoURL: URL,
        courseURL: URL,
        onItemChanged: @escaping () -> Void,
        onError: @escaping (String) -> Void
    ) {
        self.videoURL = videoURL
        self.courseURL = courseURL
        self.onItemChanged = onItemChanged
        self.onError = onError
        self._player = State(initialValue: AVPlayer(url: videoURL))
    }

    var body: some View {
        VStack(spacing: 0) {
            VideoPlayer(player: player)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
                .background(Color.appDivider)
            controlBar
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.appBackground.opacity(0.5))
        }
        .onAppear { refreshStatus() }
        .onDisappear { player.pause() }
    }

    private var controlBar: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { _ in
            HStack(spacing: 12) {
                Text(currentTimeLabel)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.appInfo)
                Spacer()
                Button {
                    Task { await fixFrame() }
                } label: {
                    HStack(spacing: 6) {
                        if isExtracting {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "camera.viewfinder")
                        }
                        Text("Fijar este frame como miniatura")
                    }
                }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(!canFixFrame)
                .buttonStyle(.borderedProminent)
                .tint(Color.appMenu)
                .help("Pausá el video y elegí el frame con el scrubber. Se exporta como \(videoURL.deletingPathExtension().lastPathComponent).jpg junto al .mp4.")
            }
            .onAppear { refreshStatus() }
        }
    }

    private var canFixFrame: Bool {
        timeControlStatus == .paused && !isExtracting
    }

    private var currentTimeLabel: String {
        let seconds = CMTimeGetSeconds(player.currentTime())
        guard seconds.isFinite, seconds >= 0 else { return "00:00" }
        return Self.formatTimecode(seconds)
    }

    private static func formatTimecode(_ seconds: Double) -> String {
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%02d:%02d", m, s)
    }

    private func refreshStatus() {
        timeControlStatus = player.timeControlStatus
    }

    private func fixFrame() async {
        isExtracting = true
        defer { isExtracting = false }
        let seconds = CMTimeGetSeconds(player.currentTime())
        let destination = videoURL.deletingPathExtension()
            .appendingPathExtension("jpg")
        let ok = await MacCourseOperations.extractAndSaveFrame(
            fromVideo: videoURL,
            atSeconds: seconds,
            to: destination
        )
        if ok {
            onItemChanged()
        } else {
            onError("No se pudo extraer el frame. Revisa la consola para más detalles.")
        }
    }
}

// MARK: - PDF preview

private struct PDFPreview: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        view.document = PDFDocument(url: url)
        return view
    }

    func updateNSView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url {
            view.document = PDFDocument(url: url)
        }
    }
}

// MARK: - HTML preview

private struct HTMLPreview: NSViewRepresentable {
    let url: URL
    let baseURL: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // The HTML viewer doesn't need JavaScript bridges for
        // Fase 10 — plain read access is enough for relative
        // links to resolve. If Fase 13+ needs to talk to the
        // host, add a `WKScriptMessageHandler` here.
        let view = WKWebView(frame: .zero, configuration: config)
        view.setValue(false, forKey: "drawsBackground")
        view.loadFileURL(url, allowingReadAccessTo: baseURL)
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        if view.url != url {
            view.loadFileURL(url, allowingReadAccessTo: baseURL)
        }
    }
}
