// LibraryStore.swift
//
// Shared state for the iOS library. Owns the `CourseIndexer` and
// exposes its snapshot to SwiftUI views as an `@Published` array.
// Replaces the pattern from `DebugLibraryView` (one indexer per view)
// so the library, the detail view, and the search screen all look at
// the same data.
//
// Fase 4 additions:
//   * `searchService: SearchService` drives the FTS5 full-text index.
//   * `refresh()` kicks off a reindex after the main indexer runs.
//     The reindex is fire-and-forget: the UI doesn't wait for it,
//     and the search results stream in as files are indexed.
//   * `searchResults` is the read-side surface used by
//     `LibraryView` to render the three-section results screen.
//   * `updateSearch(_:)` is the write-side entry point the view
//     calls from `.onChange(of: searchText)`.
//   * `highlightedItem` and `pendingSearchPosition` are how
//     `CourseDetailView` receives a "tap from search" intent: the
//     detail view reads them on appear, scrolls to the right lesson,
//     shows a banner with the intended position, and clears them
//     again so the next normal opening of the same course doesn't
//     re-trigger the banner.

import Combine
import Foundation
import Shared
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    // MARK: - Search state (Fase 4)

    /// Three-section bundle shown in the library when the user is
    /// searching. Empty when the field is empty or no matches.
    @Published private(set) var searchResults: SearchResults = .empty

    /// True while a background reindex is running. The library shows
    /// an "Indexando 35 %" banner while this is up.
    @Published private(set) var isIndexing: Bool = false

    /// Fraction in `0.0...1.0` of the current reindex pass, or
    /// `nil` when no reindex is in flight.
    @Published private(set) var indexProgress: Double? = nil

    // MARK: - Search → detail plumbing (Fase 4)

    /// When the user taps a subtitle/HTML result, the library
    /// sets this so the detail view can scroll to the right lesson
    /// and show the "min 12:34" banner. Cleared by the detail view
    /// in `onAppear`.
    @Published var highlightedItem: CourseItem?
    @Published var pendingSearchPosition: SearchPosition?

    // MARK: - Internal

    private var coverColorCache: [URL: Color] = [:]

    private let indexer: CourseIndexer
    private let fileManager: FileManager
    private let searchService: SearchService?

    init(
        indexer: CourseIndexer = CourseIndexer(),
        searchService: SearchService? = nil,
        fileManager: FileManager = .default
    ) {
        self.indexer = indexer
        self.fileManager = fileManager
        self.searchService = searchService
    }

    // MARK: - Refresh + index

    /// Re-scan the courses directory and update `courses`. Cheap to
    /// call — the indexer does a single recursive walk plus a
    /// sequential AVAsset pass for video durations. The FTS5
    /// reindex is kicked off in the background and doesn't block
    /// the UI.
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = try await indexer.index()
            courses = result
            // Covers may have changed; drop the cache so the next read
            // recomputes. The colors are cheap but we still don't want
            // to serve a stale one if the user just dropped a new
            // cover.jpg into a course.
            coverColorCache.removeAll(keepingCapacity: true)
            lastError = nil
            // Hand the new snapshot to the search service. It
            // diffs against its FTS5 metadata table and reindexes
            // only changed files. This call is fire-and-forget;
            // search results stream in as files are processed.
            searchService?.startReindex(courses: result)
        } catch {
            lastError = "\(error)"
            courses = []
        }
    }

    // MARK: - Search

    /// Called from `LibraryView` when the user types in the search
    /// field. Debounced inside the service.
    func updateSearch(_ text: String) {
        searchService?.search(text, courses: courses)
    }

    /// Called when the user clears the search field.
    func clearSearch() {
        searchService?.clear()
    }

    // MARK: - URL helpers

    /// Absolute URL for a course's directory, used to load cover images.
    /// Returns `nil` only if the Documents directory can't be located,
    /// which doesn't happen on iOS in practice.
    func courseDirectoryURL(for course: Course) -> URL? {
        guard let docs = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return docs
            .appendingPathComponent("Cursos", isDirectory: true)
            .appendingPathComponent(course.folderName, isDirectory: true)
    }

    /// Absolute URL for a course's cover image, or `nil` if the course
    /// has no `coverFileName` declared by the indexer.
    func coverURL(for course: Course) -> URL? {
        guard let coverFileName = course.coverFileName,
              let courseDir = courseDirectoryURL(for: course) else {
            return nil
        }
        return courseDir.appendingPathComponent(coverFileName)
    }

    /// Dominant color of the course's cover, ready to be used as the
    /// CTA accent (or `.appAccentFallback` if we can't pull a useful
    /// color out of it). Cached per cover URL.
    func coverColor(for course: Course) -> Color {
        guard let url = coverURL(for: course) else {
            return .appAccentFallback
        }
        if let cached = coverColorCache[url] {
            return cached
        }
        let color = CoverColorExtractor.dominantColor(of: url) ?? .appAccentFallback
        coverColorCache[url] = color
        return color
    }

    // MARK: - Course completion

    /// Mark every item in the course as completed. Used by the
    /// "Marcar curso como completado" button on the detail hero.
    /// In-memory only for Fase 3 — there's no sidecar yet, so the
    /// next index reset will lose the state. Fase 5 (sidecar) makes
    /// this persistent; the public surface here doesn't change.
    func markCourseCompleted(courseID: UUID) {
        guard let index = courses.firstIndex(where: { $0.id == courseID }) else {
            return
        }
        var updated = courses[index]
        for moduleIndex in updated.modules.indices {
            for itemIndex in updated.modules[moduleIndex].items.indices {
                var item = updated.modules[moduleIndex].items[itemIndex]
                if !item.progress.isCompleted {
                    item.progress.isCompleted = true
                    item.progress.completionMarkedAt = Date()
                }
                updated.modules[moduleIndex].items[itemIndex] = item
            }
        }
        courses[index] = updated
    }

    // MARK: - Bootstrap

    /// Factory that wires up the search service with the right DB
    /// path. Called once at app launch from `CursosIpadApp`.
    static func makeDefault() -> LibraryStore {
        let indexer = CourseIndexer()
        if let searchService = makeSearchServiceIfPossible() {
            return LibraryStore(indexer: indexer, searchService: searchService)
        }
        return LibraryStore(indexer: indexer, searchService: nil)
    }

    /// Try to create a `SearchService` rooted at the standard
    /// `Library/Application Support/cursosIpad-index/index.sqlite`.
    /// Returns `nil` if the directory can't be created or the DB
    /// can't be opened — in that case the app still works, just
    /// without full-text search.
    private static func makeSearchServiceIfPossible() -> SearchService? {
        let fm = FileManager.default
        guard let support = try? fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) else {
            return nil
        }
        let dir = support.appendingPathComponent("cursosIpad-index", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let dbURL = dir.appendingPathComponent("index.sqlite")
        let coursesRoot: URL
        if let docs = fm.urls(for: .documentDirectory, in: .userDomainMask).first {
            coursesRoot = docs.appendingPathComponent("Cursos", isDirectory: true)
        } else {
            return nil
        }
        do {
            let indexer = try SearchIndexer(databaseURL: dbURL, fileManager: fm)
            let service = SearchService(indexer: indexer, fileManager: fm, coursesRoot: coursesRoot)
            return service
        } catch {
            return nil
        }
    }
}
