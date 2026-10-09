// MacCourseOperations.swift
//
// Free functions that perform the I/O-heavy operations the Mac UI
// surfaces as buttons. Split out from the views so each helper is
// independently unit-testable and the view code stays declarative.
//
// All operations log to the console on failure (matching the
// convention of the iOS indexer and sidecar store) but never throw
// or crash — they're surfaced as booleans or values to the UI, which
// shows an alert if something went wrong.

import AppKit
import Foundation
import Shared

enum MacCourseOperations {

    // MARK: - URL helpers

    /// Absolute URL of a course's directory inside the configured library
    /// root. Returns `nil` only when `libraryRoot` itself is invalid.
    static func courseDirectoryURL(
        for course: Course,
        libraryRoot: URL
    ) -> URL {
        libraryRoot.appendingPathComponent(course.folderName, isDirectory: true)
    }

    /// Absolute URL of a course's cover image, or `nil` if the course
    /// has no `coverFileName`. Mirrors the iOS `LibraryStore.coverURL(for:)`.
    static func coverURL(
        for course: Course,
        libraryRoot: URL
    ) -> URL? {
        guard let coverFileName = course.coverFileName else { return nil }
        return courseDirectoryURL(for: course, libraryRoot: libraryRoot)
            .appendingPathComponent(coverFileName)
    }

    /// All image files at the root of a course folder, used by the
    /// "Auto-detectar" button to surface candidates. Returns an
    /// empty list if the folder can't be read.
    static func imageCandidates(at courseURL: URL) -> [URL] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: courseURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { ItemType.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    // MARK: - Import

    /// Show an `NSOpenPanel` and let the user pick a folder to import.
    /// The chosen folder is **copied** into the library root (preserving
    /// its name). Returns the new course folder URL on success, `nil`
    /// if the user cancelled.
    ///
    /// Plan §15.1 says import = "open folder"; the copy step is
    /// implicit because the library is the user's own filesystem —
    /// they want their originals preserved where they put them, and
    /// the library acts as the staging area for "what to send to the
    /// iPad later". A future "Import without copying" toggle can
    /// move the folder instead of copying it.
    @MainActor
    static func showImportPanel(into libraryRoot: URL) -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Importar curso"
        panel.message = "Elige una carpeta de curso. Se copiará a tu biblioteca."
        panel.prompt = "Importar"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let sourceURL = panel.url else {
            return nil
        }
        return importCourse(from: sourceURL, into: libraryRoot)
    }

    /// Copy `sourceURL` (a course folder) into `libraryRoot` and
    /// return the destination URL. Returns `nil` if the source is
    /// already inside the library (refuse to nest) or if the copy
    /// fails for any other reason.
    @discardableResult
    static func importCourse(from sourceURL: URL, into libraryRoot: URL) -> URL? {
        let fm = FileManager.default
        let folderName = sourceURL.lastPathComponent
        let destinationURL = libraryRoot.appendingPathComponent(folderName, isDirectory: true)

        // Refuse to import the same folder twice. The user might
        // double-click or have run a sync tool that copied it into
        // the library already; silently succeeding would just make
        // the duplicate obvious in the sidebar.
        if destinationURL.standardizedFileURL.path == sourceURL.standardizedFileURL.path {
            print("[MacCourseOperations] Refusing to copy \(sourceURL.path) onto itself")
            return nil
        }

        do {
            // `createDirectory(at:withIntermediateDirectories:true)` is a
            // no-op if the directory already exists; we use `copyItem`
            // for the actual data so the destination reflects the
            // source's contents rather than being merged.
            if fm.fileExists(atPath: destinationURL.path) {
                print("[MacCourseOperations] Destination already exists at \(destinationURL.path) — refusing to overwrite via import")
                return nil
            }
            try fm.createDirectory(
                at: libraryRoot,
                withIntermediateDirectories: true
            )
            try fm.copyItem(at: sourceURL, to: destinationURL)
            return destinationURL
        } catch {
            print("[MacCourseOperations] Failed to import \(sourceURL.path): \(error)")
            return nil
        }
    }

    // MARK: - Pick a cover image

    /// Show an `NSOpenPanel` configured for image selection. Returns
    /// the chosen URL or `nil` if the user cancelled.
    @MainActor
    static func showCoverPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.title = "Elegir portada"
        panel.message = "Elige una imagen para la portada del curso."
        panel.prompt = "Usar como portada"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image]
        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }
        return url
    }

    /// Copy `imageURL` into `courseURL` as `cover.jpg` (overwriting
    /// any existing file with that name). The sidecar's
    /// `coverFileName` stays "cover.jpg" — that's the canonical
    /// name the indexer looks for per plan §9.
    @discardableResult
    static func setCover(
        from imageURL: URL,
        for courseURL: URL
    ) -> Bool {
        let fm = FileManager.default
        let destination = courseURL.appendingPathComponent("cover.jpg", isDirectory: false)
        do {
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(at: imageURL, to: destination)
            return true
        } catch {
            print("[MacCourseOperations] Failed to set cover for \(courseURL.path): \(error)")
            return false
        }
    }

    /// Auto-detect the cover: pick the first image in the course
    /// root and rename it to `cover.jpg` so the indexer picks it up.
    /// Returns the chosen file's URL on success, `nil` if no images
    /// are available. If `cover.jpg` already exists, leaves it alone.
    @discardableResult
    static func autoDetectCover(for courseURL: URL) -> URL? {
        let fm = FileManager.default
        let existing = courseURL.appendingPathComponent("cover.jpg", isDirectory: false)
        if fm.fileExists(atPath: existing.path) {
            return existing
        }
        let candidates = imageCandidates(at: courseURL)
        guard let chosen = candidates.first else { return nil }
        guard setCover(from: chosen, for: courseURL) else { return nil }
        return existing
    }

    // MARK: - Persist metadata edits

    /// Persist a `Course` edit (title / description / cover) to the
    /// course's sidecar. Reads the existing sidecar first (if any) so
    /// we preserve `courseId` and per-item progress; only the fields
    /// the user actually edited get overwritten.
    ///
    /// Note: the `Course` passed in is the in-memory snapshot from
    /// the store; if the user renamed the course folder in Finder,
    /// the store's `folderName` already reflects that, so
    /// `courseDirectoryURL(for:libraryRoot:)` resolves correctly.
    @MainActor
    static func persistCourseMetadata(
        _ course: Course,
        libraryRoot: URL,
        title: String? = nil,
        description: String? = nil,
        coverFileName: String? = nil,
        tags: [String]? = nil
    ) async -> Bool {
        let courseURL = courseDirectoryURL(for: course, libraryRoot: libraryRoot)
        let existing = SidecarStore.read(courseURL: courseURL) ?? SidecarStore.empty(course: course)
        let updated = Sidecar(
            version: existing.version,
            courseId: existing.courseId,
            title: title ?? existing.title,
            coverFileName: coverFileName ?? existing.coverFileName,
            description: description ?? existing.description,
            tags: tags ?? existing.tags,
            items: existing.items,
            updatedAt: existing.updatedAt
        )
        do {
            try await SidecarStore.write(updated, to: courseURL)
            return true
        } catch {
            print("[MacCourseOperations] Failed to persist sidecar for \(course.folderName): \(error)")
            return false
        }
    }
}