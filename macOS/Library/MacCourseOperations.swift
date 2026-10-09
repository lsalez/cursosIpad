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
import AVFoundation
import CoreMedia
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

    // MARK: - File ops (Fase 10)

    /// `true` when `name` doesn't collide with any of `siblings`
    /// (case-insensitive — macOS HFS+/APFS treat the filesystem as
    /// case-insensitive by default, so `Lesson 1.mp4` and
    /// `lesson 1.MP4` would refer to the same file). Used by the
    /// inline rename in `MacCourseOutline` to gate the commit button.
    static func validateUnique(name: String, in siblings: [String]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return false }
        let lower = trimmed.lowercased()
        return !siblings.contains { $0.lowercased() == lower }
    }

    /// Rename the file at `oldRelativePath` inside `courseURL` to
    /// `newFilename` (a single component, not a path). Moves the
    /// file via `FileManager.moveItem`; returns the new
    /// `relativePath` on success, `nil` on any failure (empty name,
    /// collision, missing source, etc.). The caller is responsible
    /// for reindexing — the on-disk rename happens here but the
    /// in-memory `Course` snapshot in the store is stale until
    /// `MacLibraryStore.refresh()` runs.
    @discardableResult
    static func renameItem(
        at oldRelativePath: String,
        to newFilename: String,
        in courseURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = newFilename.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.contains("/") else {
            return nil
        }
        let oldURL = courseURL.appendingPathComponent(oldRelativePath, isDirectory: false)
        let directory = oldURL.deletingLastPathComponent()
        let newURL = directory.appendingPathComponent(trimmed, isDirectory: false)

        guard oldURL.standardizedFileURL != newURL.standardizedFileURL else {
            // Trivial rename to the same name — treat as success, no I/O.
            return oldRelativePath
        }
        guard !fileManager.fileExists(atPath: newURL.path) else {
            print("[MacCourseOperations] renameItem: destination already exists at \(newURL.path)")
            return nil
        }
        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            let newRelative = newURL.path
                .replacingOccurrences(of: courseURL.path + "/", with: "")
            return newRelative
        } catch {
            print("[MacCourseOperations] renameItem failed: \(error)")
            return nil
        }
    }

    /// Rename the module folder at `oldFolderName` inside `courseURL`
    /// to `newFolderName`. Same contract as `renameItem` — returns
    /// the new folder name on success, `nil` on failure. Modules
    /// can never collide with items (different directories), but
    /// can collide with sibling module folders, so the caller's
    /// uniqueness check applies.
    @discardableResult
    static func renameModule(
        at oldFolderName: String,
        to newFolderName: String,
        in courseURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let trimmed = newFolderName.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty,
              !trimmed.contains("/") else {
            return nil
        }
        let oldURL = courseURL.appendingPathComponent(oldFolderName, isDirectory: true)
        let newURL = courseURL.appendingPathComponent(trimmed, isDirectory: true)
        guard oldURL.standardizedFileURL != newURL.standardizedFileURL else {
            return oldFolderName
        }
        guard !fileManager.fileExists(atPath: newURL.path) else {
            print("[MacCourseOperations] renameModule: destination already exists at \(newURL.path)")
            return nil
        }
        do {
            try fileManager.moveItem(at: oldURL, to: newURL)
            return trimmed
        } catch {
            print("[MacCourseOperations] renameModule failed: \(error)")
            return nil
        }
    }

    /// Move a single file from one module folder to another. The
    /// `oldRelativePath` is rooted at the course; `toFolder` is the
    /// destination module's folder name (or `""` to move to the
    /// course root, where loose files live in the virtual "General"
    /// module). Returns the new `relativePath` on success.
    @discardableResult
    static func moveItemToModule(
        from oldRelativePath: String,
        toFolder destinationFolder: String,
        in courseURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let oldURL = courseURL.appendingPathComponent(oldRelativePath, isDirectory: false)
        let filename = oldURL.lastPathComponent
        let destinationDir = destinationFolder.isEmpty
            ? courseURL
            : courseURL.appendingPathComponent(destinationFolder, isDirectory: true)
        let newURL = destinationDir.appendingPathComponent(filename, isDirectory: false)
        guard !fileManager.fileExists(atPath: newURL.path) else {
            print("[MacCourseOperations] moveItemToModule: destination already exists at \(newURL.path)")
            return nil
        }
        do {
            try fileManager.createDirectory(
                at: destinationDir,
                withIntermediateDirectories: true
            )
            try fileManager.moveItem(at: oldURL, to: newURL)
            let newRelative = newURL.path
                .replacingOccurrences(of: courseURL.path + "/", with: "")
            return newRelative
        } catch {
            print("[MacCourseOperations] moveItemToModule failed: \(error)")
            return nil
        }
    }

    /// Rename a file in place within its current directory to give
    /// it a numeric prefix that places it at the target sort
    /// position. The indexer uses `localizedStandardCompare`, so a
    /// `01-` prefix sorts before `02-`, which sorts before bare
    /// names. This is the persistence mechanism for the outline's
    /// drag-to-reorder: there's no separate `order` field, so the
    /// sort is the source of truth.
    ///
    /// The new name strips any existing numeric prefix from the
    /// stem (so re-reordering doesn't pile up prefixes), then
    /// prepends `(index + 1)` zero-padded to 2 digits. If a file
    /// with the resulting name already exists, the prefix is
    /// bumped up until a free slot is found. The user can then
    /// manually clean up if they want a strict `01-, 02-, 03-…`
    /// sequence.
    @discardableResult
    static func reorderItemInPlace(
        at oldRelativePath: String,
        toIndex newIndex: Int,
        in courseURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let oldURL = courseURL.appendingPathComponent(oldRelativePath, isDirectory: false)
        let directory = oldURL.deletingLastPathComponent()
        let originalName = oldURL.lastPathComponent
        let stem = (originalName as NSString).deletingPathExtension
        let ext = (originalName as NSString).pathExtension
        let stemWithoutPrefix = stem.replacingOccurrences(
            of: #"^\d+[\s._-]?"#,
            with: "",
            options: .regularExpression
        )

        func build(prefix: Int) -> (name: String, url: URL) {
            let p = String(format: "%02d", prefix)
            let name = ext.isEmpty
                ? "\(p) \(stemWithoutPrefix)"
                : "\(p) \(stemWithoutPrefix).\(ext)"
            let url = directory.appendingPathComponent(name, isDirectory: false)
            return (name, url)
        }

        var attempt = max(1, newIndex + 1)
        var (candidateName, candidateURL) = build(prefix: attempt)
        while fileManager.fileExists(atPath: candidateURL.path),
              candidateURL.standardizedFileURL != oldURL.standardizedFileURL {
            attempt += 1
            guard attempt < 1000 else { return nil }
            (candidateName, candidateURL) = build(prefix: attempt)
        }
        guard candidateURL.standardizedFileURL != oldURL.standardizedFileURL else {
            return oldRelativePath
        }
        do {
            try fileManager.moveItem(at: oldURL, to: candidateURL)
            let newRelative = candidateURL.path
                .replacingOccurrences(of: courseURL.path + "/", with: "")
            return newRelative
        } catch {
            print("[MacCourseOperations] reorderItemInPlace failed: \(error)")
            return nil
        }
    }

    /// Rename a module folder to give it a numeric prefix. Same
    /// persistence mechanism as `reorderItemInPlace` but operating
    /// on a directory. Returns the new folder name on success.
    @discardableResult
    static func reorderModule(
        folderName oldFolderName: String,
        toIndex newIndex: Int,
        in courseURL: URL,
        fileManager: FileManager = .default
    ) -> String? {
        let oldURL = courseURL.appendingPathComponent(oldFolderName, isDirectory: true)
        let stemWithoutPrefix = oldFolderName.replacingOccurrences(
            of: #"^\d+[\s._-]?"#,
            with: "",
            options: .regularExpression
        )

        func build(prefix: Int) -> (name: String, url: URL) {
            let p = String(format: "%02d", prefix)
            let name = "\(p) \(stemWithoutPrefix)"
            let url = courseURL.appendingPathComponent(name, isDirectory: true)
            return (name, url)
        }

        var attempt = max(1, newIndex + 1)
        var (candidateName, candidateURL) = build(prefix: attempt)
        while fileManager.fileExists(atPath: candidateURL.path),
              candidateURL.standardizedFileURL != oldURL.standardizedFileURL {
            attempt += 1
            guard attempt < 1000 else { return nil }
            (candidateName, candidateURL) = build(prefix: attempt)
        }
        guard candidateURL.standardizedFileURL != oldURL.standardizedFileURL else {
            return oldFolderName
        }
        do {
            try fileManager.moveItem(at: oldURL, to: candidateURL)
            return candidateName
        } catch {
            print("[MacCourseOperations] reorderModule failed: \(error)")
            return nil
        }
    }

    /// Move a single file to the macOS Trash. Recoverable from the
    /// user's `~/.Trash`; the resultingItemURL is populated by the
    /// system if the caller wants to display the trash path in a
    /// confirmation message. Returns `true` on success.
    @discardableResult
    static func trashItem(
        at relativePath: String,
        in courseURL: URL,
        resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>? = nil
    ) -> Bool {
        let fileURL = courseURL.appendingPathComponent(relativePath, isDirectory: false)
        do {
            try FileManager.default.trashItem(
                at: fileURL,
                resultingItemURL: resultingItemURL
            )
            return true
        } catch {
            print("[MacCourseOperations] trashItem failed for \(relativePath): \(error)")
            return false
        }
    }

    /// Move a whole module folder to the macOS Trash. Same contract
    /// as `trashItem` but operates on a directory. Used by the
    /// outline's "Eliminar módulo" action.
    @discardableResult
    static func trashModule(
        folderName: String,
        in courseURL: URL,
        resultingItemURL: AutoreleasingUnsafeMutablePointer<NSURL?>? = nil
    ) -> Bool {
        let folderURL = courseURL.appendingPathComponent(folderName, isDirectory: true)
        do {
            try FileManager.default.trashItem(
                at: folderURL,
                resultingItemURL: resultingItemURL
            )
            return true
        } catch {
            print("[MacCourseOperations] trashModule failed for \(folderName): \(error)")
            return false
        }
    }

    /// Extract a video frame at `atSeconds` (relative to the start
    /// of the video) and write it as JPEG to `destinationURL`.
    /// Thin wrapper around `MacVideoThumbnailExtractor` so callers
    /// in the views can stay on the `MacCourseOperations` API
    /// surface. Used by the "Fijar este frame" preview button.
    static func extractAndSaveFrame(
        fromVideo videoURL: URL,
        atSeconds seconds: Double,
        to destinationURL: URL
    ) async -> Bool {
        let time = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        return await MacVideoThumbnailExtractor.extractFrame(
            fromVideo: videoURL,
            at: time,
            writeTo: destinationURL
        )
    }

    /// Find the first video file in any module of `courseURL`,
    /// returning its absolute `URL` plus its `durationSeconds` (read
    /// via `AVAsset` on demand — the indexer doesn't pre-compute
    /// durations per Fase 9's design). Returns `nil` if the course
    /// has no videos. Files in the root (`General` virtual module)
    /// are scanned last so a video in a real module wins.
    static func firstVideo(
        in courseURL: URL,
        fileManager: FileManager = .default
    ) async -> (url: URL, durationSeconds: Double?)? {
        let scan = ScanHelper(url: courseURL, fileManager: fileManager)
        return await scan.firstVideo()
    }

    /// Fase 10's "Auto-detectar" — keep the existing
    /// `autoDetectCover` priority (`cover.jpg` → `cover.png` → first
    /// image at root), and as a last resort extract a frame from
    /// the first video in the course at 25% of its duration and
    /// save it as `cover.jpg`. The earlier function is preserved
    /// untouched for callers that don't want the video-fallback
    /// path; this one is wired to the editor's "Auto-detectar"
    /// button.
    @discardableResult
    static func autoDetectCoverImproved(for courseURL: URL) async -> URL? {
        if let existing = autoDetectCover(for: courseURL) {
            return existing
        }
        guard let (videoURL, duration) = await firstVideo(in: courseURL) else {
            return nil
        }
        let seconds = (duration ?? 0) * 0.25
        let coverURL = courseURL.appendingPathComponent("cover.jpg", isDirectory: false)
        let ok = await extractAndSaveFrame(
            fromVideo: videoURL,
            atSeconds: seconds,
            to: coverURL
        )
        return ok ? coverURL : nil
    }
}

// MARK: - Internal scan helper

/// Walks the course directory looking for the first video. Pulled
/// out of `MacCourseOperations` so the recursion is testable in
/// isolation. The walk is shallow (one level into module folders)
/// because plan §9 says modules are the only subdirectory level
/// the app cares about.
private struct ScanHelper {
    let url: URL
    let fileManager: FileManager

    func firstVideo() async -> (url: URL, durationSeconds: Double?)? {
        let rootVideos = videosInDirectory(url)
        if let first = rootVideos.first {
            let duration = await Self.duration(of: first)
            return (first, duration)
        }
        guard let modules = try? fileManager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }
        let moduleDirs = modules.filter { dir in
            (try? dir.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
        for moduleDir in moduleDirs.sorted(by: {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }) {
            let moduleVideos = videosInDirectory(moduleDir)
            if let first = moduleVideos.first {
                let duration = await Self.duration(of: first)
                return (first, duration)
            }
        }
        return nil
    }

    private func videosInDirectory(_ directory: URL) -> [URL] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return contents
            .filter { ItemType.from(extension: $0.pathExtension) == .video }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func duration(of videoURL: URL) async -> Double? {
        await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            do {
                let cmDuration = try await asset.load(.duration)
                let seconds = CMTimeGetSeconds(cmDuration)
                return seconds.isFinite && seconds > 0 ? seconds : nil
            } catch {
                print("[ScanHelper] duration load failed for \(videoURL.lastPathComponent): \(error)")
                return nil
            }
        }.value
    }
}