// PDFViewerView.swift
//
// The "lesson view" for PDFs — replaces `CourseDetailView` entirely
// when a PDF lesson is selected, exactly the way `VideoPlayerView`
// does for video lessons. Architectural notes:
//
//   * **`.id(item.id)` is applied by the parent** (`CourseDetailView`),
//     not here. The `.id` lives OUTSIDE the `Group` that dispatches
//     by `lesson.type` (see `CourseDetailView.body`) — that's what
//     forces full reconstruction on every lesson swap and triggers
//     `dismantleUIView` on the previous `PDFView`.
//
//   * **No resume-race gates.** `PDFView.go(to:)` is synchronous
//     — by the time the representable's `makeUIView` returns, the
//     page is set. The video player needs two `@State` flags
//     (`didIssueInitialSeek` / `didReceiveFirstContentTime`) because
//     `AVPlayer.seek` is async. PDFs don't.
//
//   * **No periodic observer.** Page changes are user-driven, not
//     time-driven, so we don't need a 5s flush. The
//     `PDFViewPageChanged` notification fires once per change and
//     that's our save trigger. The `SidecarWriter` actor (Fase 5)
//     serializes concurrent writes if the user flings pages fast.
//
//   * **No search-position plumbing.** Per plan §2 #9, PDFs are
//     not in the FTS5 index, so there's no `initialStartPage` or
//     `onPositionConsumed` callback. The viewer reads
//     `item.progress.lastPage` directly for resume.
//
//   * **No `MPNowPlayingInfoCenter`.** PDFs aren't audio.
//
//   * **Thumbnail strip is a sibling view, not a subview of
//     `PDFView`.** `PDFView`'s built-in thumbnail bar is UIKit
//     toolbar-style and doesn't play nice with SwiftUI toggling.
//     A separate `PDFThumbnailRepresentable` linked to the main
//     `PDFView` via the `pdfView` property is the cleanest
//     approach for MVP.

import PDFKit
import Shared
import SwiftUI

struct PDFViewerView: View {

    // MARK: - Inputs

    let course: Course
    let item: CourseItem

    /// Back / dismiss — wired to `selectedLesson = nil` in the parent.
    let onDismiss: () -> Void

    /// Tap on a lesson in the right-side curriculum (iPad split).
    let onSelectLesson: (CourseItem) -> Void

    // MARK: - Environment

    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var library: LibraryStore

    // MARK: - Mutable state

    /// Set when the file can't be located on disk. Replaces the
    /// chrome with an error message — same UX as the video player.
    @State private var loadError: String?

    /// Resolved absolute URL of the PDF on disk. Set in `.task` from
    /// `library.itemURL(for:item:)`. `nil` means "haven't checked
    /// yet" OR "checked and missing" (the second case is also
    /// captured by `loadError` for UX purposes).
    @State private var url: URL?

    /// Live reference to the underlying `PDFView`. Published by the
    /// representable in `makeUIView` (deferred to the next runloop
    /// tick). The thumbnail strip needs this to drive selection
    /// and highlight the current page.
    @State private var pdfView: PDFView?

    /// Whether to show the thumbnail strip / column. Toggled by the
    /// top-bar button. Default off — keeps the chrome clean until
    /// the user opts in.
    @State private var showThumbnails: Bool = false

    /// Whether the PDF is in "fullscreen" reading mode — on iPad this
    /// hides the curriculum column so the PDF takes the full width;
    /// on iPhone it hides the info tabs section so the PDF takes the
    /// full vertical space (minus the top bar). Toggled by the
    /// expand / contract button in the top bar.
    @State private var isFullscreen: Bool = false

    /// Tab activa en la columna derecha del `iPadSplit`. Mismas
    /// tres pestañas que `CourseDetailView` (Contenido /
    /// Descripción / Archivos) — replica lo que hace
    /// `VideoPlayerView` y `HTMLViewerView`.
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
            // Resolve the absolute URL. This is the only thing
            // `.task` does — the rest of the setup (document load,
            // initial seek, observer registration) lives in
            // `PDFViewerRepresentable.makeUIView` and runs as soon
            // as the view appears.
            guard let resolved = library.itemURL(for: course, item: item) else {
                loadError = "Archivo no encontrado."
                return
            }
            url = resolved
        }
    }

    // MARK: - iPad split

    private var iPadSplit: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                topBar
                Divider().background(Color.appDivider)
                pdfArea
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.04))

            if !isFullscreen {
                Divider().background(Color.appDivider)
                // Misma forma que `VideoPlayerView.iPadSplit` /
                // `HTMLViewerView.iPadSplit`: tres pestañas
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
            pdfArea

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
            // y `HTMLViewerView`.
            //
            // `minimumScaleFactor` + `truncationMode(.tail)` para
            // títulos largos — evita que se corten feo cuando el
            // ancho disponible en el panel iPad sea chico por los
            // botones a los lados (thumbnail + fullscreen +
            // "Marcar como visto").
            Text(item.title)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appTitle)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Thumbnail toggle. Same icon family as the system's
            // PDFView thumbnail bar so users get visual continuity
            // with macOS / iWork.
            Button {
                showThumbnails.toggle()
            } label: {
                Image(systemName: showThumbnails
                    ? "sidebar.right"
                    : "sidebar.squares.right")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.appTitle)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.appMenu.opacity(0.08)))
            }
            .accessibilityLabel(
                showThumbnails
                    ? "Ocultar miniaturas"
                    : "Mostrar miniaturas"
            )
            .buttonStyle(.plain)

            // Fullscreen toggle. On iPad this hides the curriculum
            // column so the PDF takes the full iPad width. On iPhone
            // it hides the info-tabs section under the PDF. Same
            // button, different effect per size class — the layout
            // picks the right behavior from `isFullscreen`.
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

    // MARK: - PDF area

    /// The actual `PDFView` plus an optional thumbnail strip. The
    /// representable handles document loading, the resume seek, and
    /// the page-change observer; the view is just composition.
    ///
    /// The thumbnail strip is laid out differently per size class:
    /// iPad gets a 140 pt right-side column (the user reads
    /// top-to-bottom alongside the main view); iPhone gets a 100 pt
    /// bottom strip (the main PDF owns the top, the strip is a
    /// glanceable navigator underneath).
    @ViewBuilder
    private var pdfArea: some View {
        if let url {
            if sizeClass == .regular {
                iPadPDFArea(url: url)
            } else {
                iPhonePDFArea(url: url)
            }
        } else {
            // `.task` hasn't resolved yet (or it failed and
            // `loadError` is set, in which case the body short-
            // circuits to `errorChrome` and we never reach here).
            // Render a neutral placeholder so the chrome isn't
            // blank for a frame.
            Color.appBackground
        }
    }

    private func iPadPDFArea(url: URL) -> some View {
        HStack(spacing: 0) {
            PDFViewerRepresentable(
                url: url,
                initialPage: item.progress.lastPage,
                pdfView: $pdfView,
                onPageChanged: writePage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showThumbnails {
                Divider().background(Color.appDivider)
                PDFThumbnailRepresentable(
                    url: url,
                    parentPDFView: pdfView
                )
                .frame(width: 140)
                .background(Color.appMenu.opacity(0.04))
                .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showThumbnails)
    }

    private func iPhonePDFArea(url: URL) -> some View {
        VStack(spacing: 0) {
            PDFViewerRepresentable(
                url: url,
                initialPage: item.progress.lastPage,
                pdfView: $pdfView,
                onPageChanged: writePage
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            if showThumbnails {
                Divider().background(Color.appDivider)
                PDFThumbnailRepresentable(
                    url: url,
                    parentPDFView: pdfView
                )
                .frame(height: 100)
                .background(Color.appMenu.opacity(0.04))
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showThumbnails)
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

    /// Stub for Fase 7: returns "Sin descripción" until Fase 10 wires
    /// the Mac editor's `description` field into the sidecar. Same
    /// shape as `VideoPlayerView.descriptionText` (líneas 290-292)
    /// so the iPhone UX is parallel between the two visors.
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
    /// Mirrors `VideoPlayerView.accentColor` (líneas 321-323).
    private var accentColor: Color {
        library.coverColor(for: course)
    }

    // MARK: - Save funnel

    /// Single funnel for the sidecar write. Off-main so we don't
    /// block disk I/O on the UI thread; serialized through the
    /// `SidecarWriter` actor (Fase 5).
    ///
    /// Called from the `PDFViewPageChanged` notification observer
    /// in `PDFViewerRepresentable`. The notification fires on the
    /// main thread (per Apple's docs and our explicit `queue: .main`
    /// in `addObserver`), so dispatching to `@MainActor` is a
    /// no-op cost — the property access is what we need to be on
    /// the main actor for, not the dispatch.
    private func writePage(_ page: Int) {
        let path = item.relativePath
        let courseID = course.id
        Task { @MainActor in
            library.updateItemProgress(
                courseID: courseID,
                itemRelativePath: path,
                lastViewedAt: Date(),
                lastPage: page
            )
        }
    }
}
