// SidecarStore.swift
//
// Read/write/merge logic for `.cursosIpad.json`. The on-disk schema
// lives in `Shared.Sidecar` (see header for the contract). This file
// is shared between the iOS and macOS targets so both apps use the
// same encoder/decoder, atomic-write path, and `.bak` corruption
// recovery — Fase 9 moves it here from `iOS/Library/` because the
// macOS editor (Fase 9) needs to persist the same JSON the iOS app
// reads on its first index of a transferred course.
//
// **Public surface is a stateless namespace** (enum), mirroring
// `CoverColorExtractor` (`iOS/Library/CoverColorExtractor.swift:21`).
// The two stateful pieces — serialization and atomic disk writes —
// live in a private `SidecarWriter` actor so callers don't have to
// think about race conditions between e.g. a course-completion write
// (Fase 5) and a per-item video progress write (Fase 6).
//
// All callers inject a `FileManager` if they want to stub the
// filesystem; production code uses `.default`.
//
// **Date strategy:** every encode uses a dedicated `JSONEncoder`
// with `.iso8601` dates. Every decode mirrors that. Course Codable
// round-trips are unrelated and continue to use default date
// encoding (numeric) — keep the two encoder instances separate so a
// future change in one doesn't leak into the other.
//
// **Atomic write:** `Data.write(to:options:.atomic)` writes to a
// uniquely-named sibling tmp file and renames onto the destination
// in one syscall. POSIX guarantees the rename is atomic within a
// single filesystem; sidecar and tmp always share the course folder
// (same volume).
//
// **Corruption recovery:** when decode fails, the broken file is
// moved aside to `<name>.bak` so the user's data isn't immediately
// overwritten by the indexer's seed write. Users can recover by
// copying it back manually; meanwhile the app works with a freshly
// seeded sidecar.

import Foundation

public enum SidecarStore {

    // MARK: - Constants

    /// Filename used inside every course folder. Leading dot makes
    /// it hidden in Finder / Files on macOS — the indexer's
    /// `.skipsHiddenFiles` will skip it during filesystem walks.
    public static let fileName = ".cursosIpad.json"

    // MARK: - URL helpers

    /// Absolute URL of the sidecar that belongs to the course living
    /// at `courseURL`. Both files end up in the same directory, which
    /// is what makes the atomic-write path safe.
    public static func sidecarURL(for courseURL: URL) -> URL {
        courseURL.appendingPathComponent(fileName, isDirectory: false)
    }

    // MARK: - Read

    /// Synchronous read. Cheap enough (KB-sized file) that we keep it
    /// sync; large courses still decode in single-digit ms.
    /// Returns `nil` if the file doesn't exist or can't be decoded
    /// (with a `.bak` copy preserved in the latter case).
    public static func read(
        courseURL: URL,
        fileManager: FileManager = .default
    ) -> Sidecar? {
        let url = sidecarURL(for: courseURL)
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Sidecar.self, from: data)
        } catch {
            // Move the corrupt file aside before the next writer overwrites
            // it. Move (rename) is atomic in the same directory so even if
            // a seed write races us, the .bak either wins or is the broken
            // one — never a mix.
            let backupURL = backupURL(for: url, fileManager: fileManager)
            do {
                // If a previous .bak is around, replace it. We only keep
                // one generation; older history is discarded by design.
                if fileManager.fileExists(atPath: backupURL.path) {
                    try fileManager.removeItem(at: backupURL)
                }
                try fileManager.moveItem(at: url, to: backupURL)
                print("[SidecarStore] Moved unreadable sidecar at \(url.path) to \(backupURL.path): \(error)")
            } catch {
                print("[SidecarStore] Could not back up unreadable sidecar at \(url.path): \(error)")
            }
            return nil
        }
    }

    // MARK: - Write

    /// `async` so the serialization between concurrent writes is
    /// guaranteed by the `SidecarWriter` actor. The actor stamps the
    /// `Sidecar.updatedAt` field at write time — callers should leave
    /// it `nil`.
    public static func write(
        _ sidecar: Sidecar,
        to courseURL: URL,
        fileManager: FileManager = .default
    ) async throws {
        let url = sidecarURL(for: courseURL)
        try await sharedWriter.write(sidecar, to: url, fileManager: fileManager)
    }

    // MARK: - Factories

    /// Build a fresh sidecar for a course that has never been seen
    /// before. `courseId` is the freshly-minted `Course.id` from the
    /// indexer — this is the UUID the app will use for the course
    /// forever, as long as the on-disk file isn't deleted.
    public static func empty(course: Course) -> Sidecar {
        Sidecar(
            courseId: course.id,
            title: course.title,
            coverFileName: course.coverFileName,
            description: nil,
            tags: course.tags,
            items: [:],
            updatedAt: nil
        )
    }

    /// Build a writeable sidecar from the current in-memory state of
    /// a course. Used after a user mutation (e.g.
    /// `LibraryStore.markCourseCompleted`). Items not present in
    /// the course's current `allItems` are pruned automatically — the
    /// next write's `items` map will only contain valid
    /// relativePaths (so removing a video file from disk and then
    /// marking the course completed cleans the sidecar in one shot).
    ///
    /// Cheap and synchronous: pure data projection, no disk I/O.
    /// `updatedAt` stays `nil`; `SidecarWriter` stamps it on disk.
    /// `description` is propagated from `course` so a Mac-edited
    /// description survives the next iOS progress write (Fase 10).
    public static func snapshot(course: Course) -> Sidecar {
        var items: [String: SidecarItem] = [:]
        for item in course.allItems {
            guard !item.relativePath.isEmpty else { continue }
            items[item.relativePath] = SidecarItem(courseItem: item)
        }
        return Sidecar(
            courseId: course.id,
            title: course.title,
            coverFileName: course.coverFileName,
            description: course.description,
            tags: course.tags,
            items: items,
            updatedAt: nil
        )
    }

    // MARK: - Apply

    /// Merge persisted metadata and progress onto a freshly-built
    /// `Course`. As of Fase 10, the consumed subset is:
    ///
    ///   * `courseId` — stable identity across scans.
    ///   * `description` — Mac editor's user-written prose.
    ///   * `tags` — chip filter values for the iOS library.
    ///   * Per-item `progress` — playback position, completion, etc.
    ///
    /// Everything else (title, cover, module/item structure) stays
    /// filesystem-derived so a Finder rename flows through naturally.
    /// Sidecar items whose relativePath no longer exists in the course
    /// are silently dropped (plan §12).
    public static func apply(_ sidecar: Sidecar, to course: Course) -> Course {
        // Stable identity across scans.
        var merged = course
        merged.id = sidecar.courseId
        merged.description = sidecar.description
        merged.tags = sidecar.tags

        let progressByPath = sidecar.items
        let knownPaths = Set(course.allItems.map(\.relativePath))

        for moduleIndex in merged.modules.indices {
            for itemIndex in merged.modules[moduleIndex].items.indices {
                var item = merged.modules[moduleIndex].items[itemIndex]
                if let persisted = progressByPath[item.relativePath] {
                    item.progress = persisted.asItemProgress
                }
                merged.modules[moduleIndex].items[itemIndex] = item
            }
        }

        // Be loud about orphans in development builds; silent in
        // production is also fine because they're just stale progress
        // data that `snapshot(course:)` will drop on the next write.
        let orphanCount = sidecar.items.keys.filter { !knownPaths.contains($0) }.count
        if orphanCount > 0 {
            print("[SidecarStore] Dropped \(orphanCount) orphaned sidecar item(s) for course \(course.folderName)")
        }

        return merged
    }

    // MARK: - Internals

    private static let encoder: JSONEncoder = {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        return enc
    }()

    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return dec
    }()

    /// Single shared writer. All writes serialize through this actor
    /// regardless of which course / which caller wrote them — that's
    /// what makes button-mashing `markCourseCompleted` (Fase 5) safe
    /// alongside per-item progress writes from the future video
    /// player (Fase 6+).
    private static let sharedWriter = SidecarWriter()

    /// `.bak` lives next to the sidecar so users can find it in
    /// Finder at the same path. We append `.bak` rather than
    /// `.broken-<timestamp>` because we keep at most one generation
    /// and the `.bak` suffix is conventional.
    private static func backupURL(
        for sidecarURL: URL,
        fileManager: FileManager
    ) -> URL {
        sidecarURL.appendingPathExtension("bak")
    }

    /// Convenience for `snapshot(course:)` when the indexer's caller
    /// didn't pass a `FileManager` explicitly. The default `.default`
    /// is fine for in-memory snapshots; we resolve the URL only.
    private static func courseURL(for course: Course, fileManager: FileManager) -> URL? {
        // Courses live directly under `Documents/`, mirroring the
        // iOS indexer's layout (plan §9). Kept in sync with
        // `LibraryStore.courseDirectoryURL(for:)`.
        guard let docs = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else { return nil }
        return docs
            .appendingPathComponent(course.folderName, isDirectory: true)
    }
}

// MARK: - SidecarWriter

private actor SidecarWriter {
    func write(
        _ sidecar: Sidecar,
        to url: URL,
        fileManager: FileManager
    ) throws {
        var stamped = sidecar
        stamped.updatedAt = Date()

        let encoder: JSONEncoder = {
            let enc = JSONEncoder()
            enc.dateEncodingStrategy = .iso8601
            enc.outputFormatting = [.prettyPrinted, .sortedKeys]
            return enc
        }()
        let data = try encoder.encode(stamped)

        // Ensure the directory exists. In practice it always does
        // (we're writing inside an already-indexed course folder),
        // but the guard is cheap and keeps the writer honest if a
        // caller passes an unusual URL.
        let dir = url.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: dir.path) {
            try fileManager.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
        }

        // Atomic write: Foundation renames a uniquely-named tmp into
        // place in one syscall. No leftover `.tmp` suffix on success.
        try data.write(to: url, options: [.atomic])
    }
}
