// CursosIpadApp.swift
//
// Entry point for the iOS app.
//
// Lifecycle:
//   1. First launch (`@AppStorage("hasSeenWelcome") == false`): show
//      `WelcomeView` so the user gets a one-time orientation. Tapping
//      "Listo" flips the flag and we move on to step 2.
//   2. Normal launches: show `RootView`, which adapts to the device
//      size class — iPhone gets a `NavigationStack` with the library
//      as root and the detail pushed on tap; iPad gets a
//      `NavigationSplitView` with the library in the sidebar and the
//      detail in the right column. The split-view selection is
//      driven by an explicit `onSelectCourse` callback from the
//      library rather than `NavigationLink(value:)`, because
//      `NavigationLink` inside a `NavigationSplitView` sidebar
//      doesn't reliably update the detail column.
//
// The `LibraryStore` is created once at the app scope (via
// `LibraryStore.makeDefault()` so the FTS5 search index is wired up
// if the app sandbox supports it) and injected via `@EnvironmentObject`
// so every view (library, detail, future search) sees the same
// `courses` snapshot.

import Shared
import SwiftUI

@main
struct CursosIpadApp: App {
    @StateObject private var library = LibraryStore.makeDefault()
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false

    var body: some Scene {
        WindowGroup {
            if hasSeenWelcome {
                RootView()
                    .environmentObject(library)
            } else {
                WelcomeView()
            }
        }
    }
}

/// Top-level container. Decides between a single `NavigationStack`
/// (iPhone) and a `NavigationSplitView` (iPad) based on the current
/// horizontal size class. The library view itself is identical in
/// both cases — the split-view column switching is just chrome.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSize
    @EnvironmentObject private var library: LibraryStore

    /// Course selected in the sidebar. Used by the iPad branch to
    /// drive the detail column. On iPhone it's unused — the
    /// `NavigationStack` owns its own `path`.
    @State private var selectedCourse: Course?

    /// Push path for the iPhone `NavigationStack`.
    @State private var path: [Course] = []

    var body: some View {
        if horizontalSize == .regular {
            NavigationSplitView {
                NavigationStack {
                    LibraryView(
                        onSelectCourse: { course in
                            selectedCourse = course
                        },
                        onSelectLesson: { hit in
                            handleLessonHit(hit)
                        },
                        onSelectSubtitle: { hit in
                            handleSubtitleHit(hit)
                        },
                        onSelectHtml: { hit in
                            handleHtmlHit(hit)
                        }
                    )
                }
            } detail: {
                if let course = selectedCourse {
                    NavigationStack {
                        CourseDetailView(
                            courseID: course.id,
                            store: library,
                            initialHighlightedItemID: library.highlightedItem?.id,
                            initialPendingPosition: library.pendingSearchPosition
                        )
                    }
                } else {
                    CourseSelectionPlaceholder()
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack(path: $path) {
                LibraryView(
                    onSelectCourse: { course in
                        path.append(course)
                    },
                    onSelectLesson: { hit in
                        handleLessonHit(hit)
                    },
                    onSelectSubtitle: { hit in
                        handleSubtitleHit(hit)
                    },
                    onSelectHtml: { hit in
                        handleHtmlHit(hit)
                    }
                )
                .navigationDestination(for: Course.self) { course in
                    CourseDetailView(
                        courseID: course.id,
                        store: library,
                        initialHighlightedItemID: library.highlightedItem?.id,
                        initialPendingPosition: library.pendingSearchPosition
                    )
                }
            }
        }
    }

    // MARK: - Search result routing

    /// A lesson-title tap resolves the matching `CourseItem` and sets
    /// `highlightedItem` so the detail view can scroll to it. No
    /// `pendingSearchPosition` — there's no specific timestamp or
    /// paragraph to land on, just the lesson itself.
    private func handleLessonHit(_ hit: LessonHit) {
        let item = library.courses
            .first(where: { $0.id == hit.course.id })?
            .allItems
            .first(where: { $0.relativePath == hit.itemRelativePath })
        library.highlightedItem = item
        library.pendingSearchPosition = nil
        selectedCourse = hit.course
        path.append(hit.course)
    }

    /// A subtitle/HTML tap shares the same code path as a course tap
    /// but goes through a small "set the intent on the store" step
    /// first, so the detail view knows to highlight the matching
    /// lesson and show the "min 12:34" banner.
    private func handleSubtitleHit(_ hit: SubtitleHit) {
        let item = library.courses
            .first(where: { $0.id == hit.course.id })?
            .allItems
            .first(where: { $0.relativePath == hit.itemRelativePath })
        library.highlightedItem = item
        library.pendingSearchPosition = .subtitle(
            startSeconds: hit.startSeconds,
            itemRelativePath: hit.itemRelativePath,
            courseID: hit.course.id
        )
        selectedCourse = hit.course
        path.append(hit.course)
    }

    private func handleHtmlHit(_ hit: HtmlHit) {
        let item = library.courses
            .first(where: { $0.id == hit.course.id })?
            .allItems
            .first(where: { $0.relativePath == hit.itemRelativePath })
        library.highlightedItem = item
        library.pendingSearchPosition = .html(
            paragraphIndex: hit.paragraphIndex,
            itemRelativePath: hit.itemRelativePath,
            courseID: hit.course.id
        )
        selectedCourse = hit.course
        path.append(hit.course)
    }
}

/// Detail-column placeholder shown on iPad until the user picks a
/// course.
private struct CourseSelectionPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Selecciona un curso")
                .font(.title3.bold())
                .foregroundStyle(Color.appTitle)
            Text("Toca un curso de la biblioteca para ver su contenido.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}
