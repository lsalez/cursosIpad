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

    var body: some View {
        Group {
            if let course {
                if sizeClass == .regular {
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

    // MARK: - Tab content

    @ViewBuilder
    private func tabContent(course: Course) -> some View {
        switch selectedTab {
        case .content:
            CurriculumView(
                course: course,
                accent: accent,
                highlightedItemID: initialHighlightedItemID,
                onTapLesson: handleOpenLesson
            )
        case .description:
            // The Course model doesn't carry a description yet — the
            // sidecar (Fase 5) is the source of truth. For Fase 3 we
            // pass `nil`, so the view always shows its "Sin
            // descripción." placeholder.
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

    private func handleOpenLesson(_ item: CourseItem) {
        // If we got here from a search result, keep the position
        // banner visible while the user explores the curriculum. The
        // position is per-course, not per-item, so we don't clear
        // it on a normal tap.
        let phase: String
        switch item.type {
        case .video: phase = "Fase 6"
        case .pdf: phase = "Fase 7"
        case .html: phase = "Fase 8"
        }
        pendingLessonNotice = PendingLessonNotice(
            title: "Próximamente",
            message: "El visor de \(item.type.label) llega en \(phase). Lección: \(item.title)."
        )
    }

    private func handleMarkCompleted() {
        store.markCourseCompleted(courseID: courseID)
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
