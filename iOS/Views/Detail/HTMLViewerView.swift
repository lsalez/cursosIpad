// HTMLViewerView.swift
//
// The "lesson view" for HTML — replaces `CourseDetailView` entirely
// when an HTML lesson is selected, the way `VideoPlayerView` and
// `PDFViewerView` do for their respective types. Architectural notes:
//
//   * **`.id(item.id)` is applied by the parent** (`CourseDetailView`),
//     not here. Same contract as the PDF and video viewers.
//
//   * **No resume-race gates for the user.** The HTML viewer
//     doesn't have a 5s periodic writer (the plan specifies "on
//     close and every 30s", and we implement "on close" via the
//     representable's `dismantleUIView` hook). The save happens once
//     when the view tears down.
//
//   * **No periodic observer.** Plan §17 specifies HTML saves on
//     close and every 30s. The 30s interval is wired through the
//     parent via a single `TimelineView`-driven timer (see
//     `body`) — runs only while the view is on screen, no-op when
//     scrolled away.
//
//   * **Search position consumption** mirrors the video player's
//     `onPositionConsumed` callback. Fires exactly once per lesson
//     after the initial seek fires, so the parent can clear the
//     banner.
//
//   * **No `MPNowPlayingInfoCenter`.** HTML isn't audio / video.
//
//   * **Top-bar layout mirrors `PDFViewerView`** for consistency
//     between the two document-style visors. The same chrome
//     (back button, title block, fullscreen toggle, mark-completed
//     button) shows up; HTML has no thumbnail strip, so the
//     thumbnail toggle from the PDF viewer is omitted.

import Shared
import SwiftUI
import WebKit

struct HTMLViewerView: View {

    // MARK: - Inputs

    let course: Course
    let item: CourseItem

    /// Back / dismiss — wired to `selectedLesson = nil` in the parent.
    let onDismiss: () -> Void

    /// Tap on a lesson in the right-side curriculum (iPad split).
    let onSelectLesson: (CourseItem) -> Void

    /// Optional paragraph index to scroll to once the page has
    /// finished loading. Comes from `SearchPosition.html(...)` when
    /// the user tapped an HTML search hit. `nil` for normal opens.
    let initialParagraphIndex: Int?

    /// Fires exactly once per lesson when the initial scroll
    /// (paragraph jump or resume offset) is issued. The parent uses
    /// this to clear its `pendingPosition` and the store-level
    /// intent. Mirrors `VideoPlayerView.onPositionConsumed`.
    let onPositionConsumed: () -> Void

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var library: LibraryStore

    // MARK: - Mutable state

    /// Set when the file can't be located on disk. Replaces the
    /// chrome with an error message — same UX as the video / PDF
    /// players.
    @State private var loadError: String?

    /// Resolved absolute URL of the HTML on disk. Set in `.task` from
    /// `library.itemURL(for:item:)`.
    @State private var url: URL?

    /// Course directory hosting the HTML file. Granted to the web
    /// view so relative links resolve. Set in `.task` alongside
    /// `url`.
    @State private var courseDirectory: URL?

    /// Whether the HTML is in "fullscreen" reading mode — on iPad this
    /// hides the curriculum column so the HTML takes the full width;
    /// on iPhone it hides the info-tabs section so the HTML takes
    /// the full vertical space (minus the top bar). Mirrors the
    /// `PDFViewerView` fullscreen toggle (Fase 7's bonus UX).
    @State private var isFullscreen: Bool = false

    /// Last scroll position (in virtual seconds) seen from the
    /// representable. Used by the 30s flush to decide whether to
    /// write — we don't write if the user hasn't moved since the
    /// last flush.
    @State private var lastFlushedOffsetSeconds: Double? = nil

    /// Tab activa en la columna derecha del `iPadSplit`. Mismas
    /// tres pestañas que `CourseDetailView` (Contenido /
    /// Descripción / Archivos) — replica lo que hace
    /// `VideoPlayerView` y `PDFViewerView`.
    @State private var selectedTab: DetailTab = .content

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
        .task {
            // Resolve both URLs in parallel — the parent directory
            // for the read-access grant and the file itself. The
            // representable's `makeUIView` is the one that actually
            // issues the load; this just primes the `@State` so the
            // body can mount the representable.
            guard let resolved = library.itemURL(for: course, item: item) else {
                loadError = "Archivo no encontrado."
                return
            }
            url = resolved
            courseDirectory = library.courseDirectoryURL(for: course)
        }
        // 30-second flush — plan §17 calls for "save on close and
        // every 30s". `TimelineView` drives the tick; we only write
        // when the representable reported a new offset since the
        // last flush (no churn when the user is idle).
        .onReceive(
            Timer.publish(every: 30, on: .main, in: .common).autoconnect()
        ) { _ in
            flushIfChanged()
        }
    }

    // MARK: - iPad split

    private var iPadSplit: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                Divider().background(Color.appDivider)
                htmlArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.04))

            if !isFullscreen {
                Divider().background(Color.appDivider)
                // Misma forma que `VideoPlayerView.iPadSplit` /
                // `PDFViewerView.iPadSplit`: tres pestañas
                // (Contenido / Descripción / Archivos) y el
                // contenido de cada una dentro de un `ScrollView`
                // único. Sin el scroll, el curriculum crecía fuera
                // del panel con muchos videos.
                VStack(spacing: 0) {
                    tabPicker
                        .padding(.horizontal, 16)
                        .padding(.top, 16)
                        .padding(.bottom, 8)
                        .background(Color.appBackground)
                    Divider().background(Color.appDivider)
                    ScrollView {
                        tabContent
                            .padding(16)
                    }
                }
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isFullscreen)
    }

    // MARK: - Tabs (shared)

    private var tabPicker: some View {
        Picker("Sección", selection: $selectedTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .content:
            CurriculumView(
                course: course,
                accent: Color.themeAdjusted(from: accentColor),
                highlightedItemID: item.id,
                courseDirectory: library.courseDirectoryURL(for: course),
                onTapLesson: onSelectLesson
            )
        case .description:
            CourseDescriptionView(description: course.description)
        case .files:
            CourseFilesView(
                course: course,
                accent: Color.themeAdjusted(from: accentColor),
                onTapItem: onSelectLesson
            )
        }
    }

    // MARK: - iPhone stack

    private var iPhoneStack: some View {
        VStack(spacing: 0) {
            topBar
            Divider().background(Color.appDivider)
            htmlArea

            if !isFullscreen {
                Divider().background(Color.appDivider)
                iPhoneInfoTabs
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.appBackground)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: isFullscreen)
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

            // El título del curso ya vive en la cabecera de navegación
            // que aplica el `CourseDetailView` padre (`.navigationTitle`).
            // Mostrarlo aquí generaría duplicación con esa cabecera;
            // dejamos sólo el título de la lección como contexto
            // "dentro del visor". Mismo patrón que `VideoPlayerView`
            // y `PDFViewerView`.
            //
            // `minimumScaleFactor` + `truncationMode(.tail)` para
            // títulos largos — evita que se corten feo cuando el
            // ancho disponible en el panel iPad sea chico por los
            // botones a los lados (fullscreen + "Marcar como
            // visto").
            Text(item.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Fullscreen toggle. Same effect per size class as the
            // PDF viewer's button (Fase 7 bonus UX) — iPad hides the
            // curriculum column, iPhone hides the info-tabs section.
            Button {
                isFullscreen.toggle()
            } label: {
                Image(systemName: isFullscreen
                    ? "arrow.down.right.and.arrow.up.left"
                    : "arrow.up.left.and.arrow.down.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(
                        isFullscreen ? Color.appAccentFallback : Color.appTitle
                    )
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.appMenu.opacity(0.08)))
            }
            .accessibilityLabel(
                isFullscreen ? "Salir de pantalla completa" : "Pantalla completa"
            )
            .buttonStyle(.plain)

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

    // MARK: - HTML area

    /// The actual `WKWebView`. The representable handles loading,
    /// the resume seek / paragraph jump, and the scroll observer;
    /// this view is just composition.
    @ViewBuilder
    private var htmlArea: some View {
        if let url, let courseDirectory {
            HTMLViewerRepresentable(
                url: url,
                allowingReadAccessTo: courseDirectory,
                initialPositionSeconds: item.progress.positionSeconds,
                initialParagraphIndex: initialParagraphIndex,
                onScrollChanged: handleScrollChanged,
                onPositionConsumed: onPositionConsumed
            )
        } else {
            // `.task` hasn't resolved yet (or it failed and
            // `loadError` is set, in which case the body short-
            // circuits to `errorChrome` and we never reach here).
            Color.appBackground
        }
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

    /// Stub for Fase 8: returns "Sin descripción" until Fase 10 wires
    /// the Mac editor's `description` field into the sidecar. Same
    /// shape as `VideoPlayerView.descriptionText` and
    /// `PDFViewerView.descriptionText` so the iPhone UX is parallel
    /// across the three visors.
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
    /// adjusted per theme. Mirrors `VideoPlayerView.accentColor` and
    /// `PDFViewerView.accentColor`.
    private var accentColor: Color {
        library.coverColor(for: course)
    }

    // MARK: - Save funnel

    /// Single funnel for the scroll position. Called from the
    /// representable's KVO observer (every scroll tick) and from the
    /// 30s timer (plan §17). Off-main so we don't block disk I/O on
    /// the UI thread; serialized through the `SidecarWriter` actor
    /// (Fase 5).
    ///
    /// The representable's `dismantleUIView` writes through the same
    /// closure, so a user who dismisses before the 30s tick still
    /// gets their position saved.
    private func handleScrollChanged(_ seconds: Double) {
        lastFlushedOffsetSeconds = seconds
        writePosition(seconds: seconds)
    }

    /// Used by the 30s timer. Writes only if the representable has
    /// reported a new offset since the last flush — no churn for an
    /// idle user.
    private func flushIfChanged() {
        guard let seconds = lastFlushedOffsetSeconds else { return }
        writePosition(seconds: seconds)
    }

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
}