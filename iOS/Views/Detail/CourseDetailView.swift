// CourseDetailView.swift
//
// The iOS course detail screen. Composes:
//
//   * `CourseHeroView` — cover, title, tags, dynamic CTA, progress,
//     "marcar como completado".
//   * A segmented tab picker (Contenido / Descripción / Archivos) and
//     the matching tab content (`CurriculumView`,
//     `CourseDescriptionView`, `CourseFilesView`).
//   * (Fase 4) `SearchPositionBanner` shown when the user got here
//     by tapping a search result. The banner carries the intended
//     position; the actual playback/scroll is wired up in Fase 6/8.
//
// On iPhone the layout is a single vertical `ScrollView` (hero on
// top, tabs, content). On iPad it switches to an internal split: the
// hero takes the left 40% and the tab content the right 60% — both
// inside a single `NavigationStack` column so the tab picker remains
// visible at the top of the right column.
//
// The view takes a `courseID: UUID` rather than a `Course` snapshot.
// We look up the live `Course` from `LibraryStore` on every render so
// mutations like "marcar curso como completado" propagate to the
// detail without the parent having to re-navigate. (The previous
// `let course: Course` shape made the detail stale: the progress bar
// and CTA would never update after the user toggled completion.)
//
// Tapping a lesson currently raises a "Próximamente" alert (visors
// land in Fases 6/7/8).

import Shared
import SwiftUI

struct CourseDetailView: View {
    let courseID: UUID
    let store: LibraryStore
    let initialHighlightedItemID: UUID?
    let initialPendingPosition: SearchPosition?

    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var selectedTab: DetailTab
    @State private var pendingLessonNotice: PendingLessonNotice?
    @State private var pendingPosition: SearchPosition?

    /// Lesson currently being watched. `nil` → normal detail (hero +
    /// tabs). Non-nil → `VideoPlayerView` replaces the body. Tapping
    /// a video lesson in `CurriculumView` sets this; the back button
    /// in the player clears it. The `.id(item.id)` modifier on the
    /// player view (in `body`) forces full reconstruction on every
    /// lesson swap — without it the underlying `AVPlayer` would
    /// silently keep playing the *old* URL when the user navigates
    /// to a new lesson in the iPad split curriculum.
    @State private var selectedLesson: CourseItem?

    init(
        courseID: UUID,
        store: LibraryStore,
        initialHighlightedItemID: UUID? = nil,
        initialPendingPosition: SearchPosition? = nil
    ) {
        self.courseID = courseID
        self.store = store
        self.initialHighlightedItemID = initialHighlightedItemID
        self.initialPendingPosition = initialPendingPosition
        _selectedTab = State(initialValue: .content)
        _pendingPosition = State(initialValue: initialPendingPosition)
    }

    /// The current `Course` from the store. Reading `store.courses`
    /// here makes the view observe the published array, so any
    /// mutation in the store (e.g. `markCourseCompleted`) re-renders
    /// the detail with the fresh state.
    private var course: Course? {
        store.courses.first(where: { $0.id == courseID })
    }

    /// The course accent (theme-adjusted) derived from the cover. We
    /// compute it once per render rather than per child so all the
    /// children agree.
    private var accent: Color {
        guard let course else { return Color.appAccentFallback }
        return Color.themeAdjusted(from: store.coverColor(for: course))
    }

    // MARK: - iPhone layout

    private func iPhoneStack(course: Course) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let pendingPosition {
                    SearchPositionBanner(position: pendingPosition)
                }
                CourseHeroView(
                    course: course,
                    store: store,
                    accent: accent,
                    onOpenLesson: handleOpenLesson,
                    onMarkCompleted: handleMarkCompleted
                )
                tabPicker
                tabContent(course: course)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
        }
    }

    // MARK: - iPad split

    private func iPadSplit(course: Course) -> some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let pendingPosition {
                        SearchPositionBanner(position: pendingPosition)
                    }
                    CourseHeroView(
                        course: course,
                        store: store,
                        accent: accent,
                        onOpenLesson: handleOpenLesson,
                        onMarkCompleted: handleMarkCompleted
                    )
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .frame(width: nil)
            .frame(idealWidth: 360, maxWidth: 460)
            .background(Color.appBackground)

            Divider()
                .background(Color.appDivider)

            VStack(spacing: 0) {
                tabPicker
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 8)
                    .background(Color.appBackground)
                Divider()
                    .background(Color.appDivider)
                ScrollView {
                    tabContent(course: course)
                        .padding(16)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Missing course

    private var missingCoursePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Curso no disponible")
                .font(.headline)
                .foregroundStyle(Color.appTitle)
            Text("Este curso ya no está en la biblioteca. Vuelve a la lista para re-escanear.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Tab picker

    private var tabPicker: some View {
        Picker("Sección", selection: $selectedTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab.title).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    var body: some View {
        Group {
            if let course {
                if let lesson = selectedLesson {
                    // Lesson view — replaces the normal detail chrome
                    // when a lesson is being viewed. The dispatch by
                    // `lesson.type` lives in `lessonView(course:lesson:)`
                    // below as a separate computed property; the
                    // compiler can't type-check a large `switch` in
                    // a ViewBuilder inline, so we extract it.
                    //
                    // **The `.id(lesson.id)` MUST live outside the
                    // `Group`.** It forces full SwiftUI
                    // reconstruction on every lesson swap, which is
                    // what triggers `dismantleUIViewController` (video)
                    // and `dismantleUIView` (PDF) on the old viewer
                    // before the new one mounts. Without it, a swap
                    // PDF-A → PDF-B would re-use the same `PDFView`
                    // identity and the old `PDFDocument` would stay
                    // attached in memory until the next `go(to:)`.
                    lessonView(course: course, lesson: lesson)
                        .id(lesson.id)
                } else if sizeClass == .regular {
                    iPadSplit(course: course)
                } else {
                    iPhoneStack(course: course)
                }
            } else {
                missingCoursePlaceholder
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle(course?.title ?? "Curso")
        .navigationBarTitleDisplayMode(.inline)
        // Pull the search intent from the store on appear. The store
        // may have been set by `LibraryView` when the user tapped a
        // result, or by `RootView` directly when the iPad split
        // route doesn't go through the library.
        .onAppear {
            if let item = store.highlightedItem, item.id == courseID {
                pendingPosition = store.pendingSearchPosition
            } else if initialHighlightedItemID != nil {
                pendingPosition = initialPendingPosition
            }
        }
        .onDisappear {
            // Clear the store-level intent so the same course opened
            // normally later doesn't re-show the banner.
            if store.highlightedItem?.id == courseID {
                store.highlightedItem = nil
                store.pendingSearchPosition = nil
            }
        }
        .onChange(of: selectedLesson) { _, newValue in
            // Closing the player (lesson → nil) is the natural clear
            // signal for the per-course pending position. Same shape
            // as the .onDisappear clear above, but covers the case
            // where the user dismisses via the player's back button
            // without leaving the detail.
            if newValue == nil {
                clearPendingPositionIfMatching()
            }
        }
        .alert(
            pendingLessonNotice?.title ?? "",
            isPresented: Binding(
                get: { pendingLessonNotice != nil },
                set: { if !$0 { pendingLessonNotice = nil } }
            ),
            presenting: pendingLessonNotice
        ) { _ in
            Button("OK", role: .cancel) { pendingLessonNotice = nil }
        } message: { notice in
            Text(notice.message)
        }
    }

    // MARK: - Lesson dispatch (video / PDF / HTML)

    /// Dispatches to the right viewer per `lesson.type`. Extracted
    /// from `body` because the compiler can't type-check a large
    /// `switch` in a `ViewBuilder` inline — that's the "expression
    /// too complex" error that bites every SwiftUI project once a
    /// viewer-dispatch `switch` grows past ~3 cases with non-trivial
    /// view arguments.
    @ViewBuilder
    private func lessonView(course: Course, lesson: CourseItem) -> some View {
        switch lesson.type {
        case .video:
            VideoPlayerView(
                course: course,
                item: lesson,
                initialStartSeconds: pendingPosition?.startSecondsForVideo,
                onDismiss: { selectedLesson = nil },
                onSelectLesson: handleOpenLesson,
                onPositionConsumed: consumePendingPosition
            )
        case .pdf:
            PDFViewerView(
                course: course,
                item: lesson,
                onDismiss: { selectedLesson = nil },
                onSelectLesson: handleOpenLesson
            )
        case .html:
            HTMLViewerView(
                course: course,
                item: lesson,
                onDismiss: { selectedLesson = nil },
                onSelectLesson: handleOpenLesson,
                initialParagraphIndex: pendingPosition?.paragraphIndexForHTML,
                onPositionConsumed: consumePendingPosition
            )
        }
    }

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(course: Course) -> some View {
        switch selectedTab {
        case .content:
            CurriculumView(
                course: course,
                accent: accent,
                highlightedItemID: initialHighlightedItemID,
                courseDirectory: store.courseDirectoryURL(for: course),
                onTapLesson: handleOpenLesson
            )
        case .description:
            // The Course model doesn't carry a description yet — the
            // sidecar (Fase 5) is the source of truth. We pass `nil`,
            // so the view always shows its "Sin descripción."
            // placeholder. Fase 10 will widen this when the Mac
            // editor populates `description` on the sidecar.
            CourseDescriptionView(description: nil)
        case .files:
            CourseFilesView(
                course: course,
                accent: accent,
                onTapItem: handleOpenLesson
            )
        }
    }

    // MARK: - Actions

    /// Tap on a lesson in the curriculum, the files tab, or the iPad
    /// split's curriculum column. Video, PDF, and HTML lessons get
    /// pushed / swapped into their respective viewers. The pending
    /// position banner stays visible until the active viewer
    /// actually consumes the seek (see `consumePendingPosition`).
    private func handleOpenLesson(_ item: CourseItem) {
        switch item.type {
        case .video:
            // `selectedLesson` change re-renders the body with a fresh
            // `VideoPlayerView` (`.id(item.id)` on the player call,
            // see above). The pending-position banner stays visible
            // until the player actually consumes the seek — see
            // `consumePendingPosition`.
            selectedLesson = item
        case .pdf:
            // Same shape as the video branch. `PDFViewerView` reads
            // `item.progress.lastPage` directly for the resume seek;
            // no pending-position plumbing because PDFs are not in
            // the FTS5 search index (plan §2 #9).
            selectedLesson = item
        case .html:
            // Same shape as the video branch. `HTMLViewerView` reads
            // `item.progress.positionSeconds` for resume (saved as
            // virtual seconds from the scroll offset, see
            // `HTMLViewerRepresentable.offset(from:)`), and consumes
            // `pendingPosition.paragraphIndexForHTML` to jump to a
            // search-hit paragraph on first load.
            selectedLesson = item
        }
    }

    private func handleMarkCompleted() {
        store.markCourseCompleted(courseID: courseID)
    }

    /// Called by `VideoPlayerView.onPositionConsumed` when the initial
    /// seek fires. Clears the per-course banner state both here and on
    /// the store, so a re-open of the same course from search doesn't
    /// re-trigger it. PDF/HTML pending positions are also cleared to
    /// match — they get the same treatment once their visors land.
    private func consumePendingPosition() {
        pendingPosition = nil
        if store.highlightedItem?.id == courseID {
            store.highlightedItem = nil
            store.pendingSearchPosition = nil
        }
    }

    /// Same clearing pattern as `consumePendingPosition` but used
    /// when the player is dismissed (back button) without ever
    /// applying a seek — covers the case where the user opens the
    /// player on a different lesson than the one the banner pointed
    /// at, or never starts playback.
    private func clearPendingPositionIfMatching() {
        guard let pos = pendingPosition else { return }
        switch pos {
        case .subtitle(_, _, let id), .html(_, _, let id):
            if id == courseID {
                consumePendingPosition()
            }
        }
    }
}

// MARK: - SearchPosition → startSeconds accessor

private extension SearchPosition {
    /// Returns the seconds to seek the video to, or `nil` for HTML
    /// positions (which carry a paragraph index, not a timestamp).
    /// Lets `CourseDetailView` pass a single `Double?` to
    /// `VideoPlayerView` regardless of position shape.
    var startSecondsForVideo: Double? {
        if case let .subtitle(seconds, _, _) = self { return seconds }
        return nil
    }

    /// Returns the 1-based paragraph index to scroll an HTML viewer
    /// to, or `nil` for video positions. Lets `CourseDetailView`
    /// pass a single `Int?` to `HTMLViewerView` regardless of
    /// position shape. Mirrors `startSecondsForVideo` above.
    var paragraphIndexForHTML: Int? {
        if case let .html(index, _, _) = self { return index }
        return nil
    }
}

// MARK: - "Marcar como completado" alert payload

private struct PendingLessonNotice: Identifiable {
    let title: String
    let message: String
    var id: String { title + message }
}

private extension ItemType {
    /// Spanish label for the alert copy.
    var label: String {
        switch self {
        case .video: return "video"
        case .pdf: return "PDF"
        case .html: return "HTML"
        }
    }
}
