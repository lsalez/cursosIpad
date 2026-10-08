// LibraryStore.swift
//
// Shared state for the iOS library. Owns the `CourseIndexer` and exposes
// its snapshot to SwiftUI views as an `@Published` array. Replaces the
// pattern from `DebugLibraryView` (one indexer per view) so the
// library, the future detail view, and the future search screen all
// look at the same data.
//
// On Fase 2 we only need:
//   - `courses` snapshot
//   - `refresh()` to re-scan
//   - loading / error state
//
// Fase 5 (sidecar) and Fase 12 (USB detection) will hang more behavior
// off this object without changing the public surface.

import Combine
import Foundation
import Shared
import SwiftUI

@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    /// Cached extraction of the cover image's dominant color, keyed by
    /// the absolute URL of the cover file. Computed lazily by
    /// `coverColor(for:)`; flushed by `refresh()` because the cover
    /// file may have changed on disk.
    private var coverColorCache: [URL: Color] = [:]

    private let indexer: CourseIndexer
    private let fileManager: FileManager

    init(
        indexer: CourseIndexer = CourseIndexer(),
        fileManager: FileManager = .default
    ) {
        self.indexer = indexer
        self.fileManager = fileManager
    }

    /// Re-scan the courses directory and update `courses`. Cheap to call
    /// — the indexer does a single recursive walk plus a sequential
    /// AVAsset pass for video durations.
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
        } catch {
            lastError = "\(error)"
            courses = []
        }
    }

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

    /// Mark every item in the course as completed. Used by the
    /// "Marcar curso como completado" button on the detail hero.
    ///
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
}
