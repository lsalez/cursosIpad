// SearchIndexer.swift
//
// The orchestrator for the full-text search subsystem. Wraps a
// `SearchIndexDatabase` in an `actor` so the SQLite connection is
// always accessed serially, and exposes a single high-level
// `reindex(courses:coursesRoot:)` entry point that the rest of the
// app calls whenever the library snapshot changes.
//
// Responsibilities:
//
//   * **Walk the filesystem.** Iterate over every course folder and
//     discover files that we know how to index (`.srt`, `.vtt`,
//     `.html`, `.htm`).
//   * **Pair subtitles to videos.** A `.srt` named like
//     `bienvenido.srt` belongs to `bienvenido.mp4` (same basename).
//     We rewrite the subtitle's `lesson_path` to the video's path
//     so tapping a subtitle result can resolve to a lesson.
//   * **Diff against the indexed_files metadata table** and only
//     re-index files whose mtime changed (or that are new). This is
//     the "incremental" part of Fase 4's contract.
//   * **Drive the parsers** (`SubtitleIndexer.extract`,
//     `HtmlIndexer.extractBlocks`) and write the resulting rows to
//     the database.
//   * **Prune deleted courses** — when a course folder disappears
//     from the latest snapshot, drop its rows from both tables.
//   * **Emit progress** through an `AsyncStream<Progress>` so the
//     UI can show a "Indexando 35 %" banner without polling.
//   * **Honor cancellation.** Every file boundary checks
//     `Task.checkCancellation()` so a pull-to-refresh during a
//     reindex can abort the old one in well under a second.
//
// **Threading:** the actor's serial executor owns the SQLite
// connection and the in-memory state. All of the indexing work
// (filesystem walk, HTML extraction, subtitle parsing, SQLite
// inserts) happens off the main thread.

import Foundation
import os.log
import Shared

private let logger = Logger(subsystem: "mx.salez.cursosipad", category: "search")

public actor SearchIndexer {

    // MARK: - Public types

    public struct Progress: Sendable, Equatable {
        public var processed: Int
        public var total: Int

        public init(processed: Int, total: Int) {
            self.processed = processed
            self.total = total
        }

        public static let unknown = Progress(processed: 0, total: 0)

        public var fraction: Double {
            total == 0 ? 0 : Double(processed) / Double(total)
        }
    }

    public enum IndexerError: Error, LocalizedError {
        case notReady

        public var errorDescription: String? {
            switch self {
            case .notReady: return "SearchIndexer is not initialized."
            }
        }
    }

    // MARK: - State

    private let database: SearchIndexDatabase
    private let fileManager: FileManager

    /// The in-flight reindex task, if any. Replaced (after
    /// cancellation) on every new `reindex(...)` call.
    private var currentTask: Task<Void, Never>?

    /// Stream of progress updates. The producer (the reindex task)
    /// writes into the continuation; the consumer (the SwiftUI
    /// binding) reads via `.makeStream()` semantics: a fresh stream
    /// is built every time someone asks for it.
    private var progressContinuation: AsyncStream<Progress>.Continuation?
    private let progressStream: AsyncStream<Progress>

    // MARK: - Init

    public init(databaseURL: URL, fileManager: FileManager = .default) throws {
        self.database = try SearchIndexDatabase(fileURL: databaseURL)
        self.fileManager = fileManager
        var continuation: AsyncStream<Progress>.Continuation!
        self.progressStream = AsyncStream<Progress> { c in
            continuation = c
        }
        self.progressContinuation = continuation
    }

    deinit {
        progressContinuation?.finish()
        database.close()
    }

    // MARK: - Public API

    /// A stream of progress updates. Each call returns the same
    /// underlying stream — the caller is expected to consume it
    /// once (typically as a `.task` modifier on the relevant view).
    public var progressUpdates: AsyncStream<Progress> {
        progressStream
    }

    /// Cancel the in-flight reindex, if any. No-op when nothing is
    /// running. The cancellation is cooperative: the running task
    /// will see `Task.checkCancellation()` and bail.
    public func cancelCurrent() {
        currentTask?.cancel()
    }

    /// Run an incremental reindex based on the latest course
    /// snapshot. Cancels any in-flight reindex first so the caller
    /// can fire-and-forget on every `LibraryStore.refresh()` without
    /// piling up work.
    public func reindex(courses: [Course], coursesRoot: URL) {
        // Cancel previous and start fresh.
        cancelCurrent()
        let task = Task { [weak self] in
            guard let self else {
                return
            }
            await self.runReindex(courses: courses, coursesRoot: coursesRoot)
        }
        currentTask = task
    }

    /// Run a single FTS5 query and return matching hits (already
    /// ordered by rank, capped at `limit`). The caller formats the
    /// snippet delimiters into an `AttributedString` for display.
    public func search(query: String, limit: Int = 30) async throws -> [SearchIndexDatabase.SearchHit] {
        try database.search(query: query, limit: limit)
    }

    // MARK: - Reindex body

    private func runReindex(courses: [Course], coursesRoot: URL) async {
        // Step 1: enumerate everything indexable on disk.
        let files = collectIndexableFiles(courses: courses, coursesRoot: coursesRoot)
        logger.notice("walk found \(files.count) indexable file(s)")
        emitProgress(processed: 0, total: files.count)

        // Step 2: diff against the metadata table.
        let toReindex: [SearchIndexDatabase.FileOnDisk]
        do {
            toReindex = try database.filesToReindex(onDisk: files)
        } catch {
            logger.error("filesToReindex failed: \(String(describing: error))")
            emitProgress(processed: 0, total: 0)
            return
        }
        logger.notice("diff: \(toReindex.count) file(s) need (re)indexing")

        // Step 3: process each file (with cooperative cancellation).
        var processed = 0
        for file in toReindex {
            if Task.isCancelled {
                logger.notice("cancelled after \(processed) file(s)")
                return
            }
            do {
                try await indexOneFile(file: file, coursesRoot: coursesRoot)
                logger.notice("indexed \(file.courseKey, privacy: .public)/\(file.lessonPath, privacy: .public) kind=\(file.kind.rawValue, privacy: .public)")
            } catch {
                logger.error("failed to index \(file.courseKey, privacy: .public)/\(file.lessonPath, privacy: .public): \(String(describing: error))")
            }
            processed += 1
            // Cancel-check every 10 files so a large reindex can be
            // aborted quickly without the overhead of checking on
            // every file.
            if processed % 10 == 0 {
                if Task.isCancelled { return }
                emitProgress(processed: processed, total: toReindex.count)
            }
        }

        // Step 4: prune rows for courses that disappeared.
        let currentKeys = Set(courses.map(\.folderName))
        do {
            let deleted = try database.detectDeletedCourseKeys(currentKeys: currentKeys)
            for key in deleted {
                if Task.isCancelled { return }
                try database.deleteAllForCourse(courseKey: key)
            }
            if !deleted.isEmpty {
                print("[SearchIndexer] pruned \(deleted.count) deleted course(s)")
            }
        } catch {
            print("[SearchIndexer] detectDeletedCourseKeys failed: \(error)")
        }

        emitProgress(processed: toReindex.count, total: toReindex.count)
        logger.notice("reindex complete: \(toReindex.count) file(s) processed of \(files.count) seen")
    }

    private func emitProgress(processed: Int, total: Int) {
        progressContinuation?.yield(Progress(processed: processed, total: total))
    }

    // MARK: - Filesystem walk

    /// Build the on-disk list of indexable files for the given
    /// courses. Each entry carries the mtime we use for the diff.
    private func collectIndexableFiles(
        courses: [Course],
        coursesRoot: URL
    ) -> [SearchIndexDatabase.FileOnDisk] {
        var out: [SearchIndexDatabase.FileOnDisk] = []
        for course in courses {
            let courseURL = coursesRoot.appendingPathComponent(
                course.folderName,
                isDirectory: true
            )
            // A subtitle file is paired to a video with the same
            // basename. We don't actually need the video file to
            // exist for indexing — but knowing the video's path is
            // what lets a result tap resolve to a lesson. The
            // CourseIndexer already walked the tree; we could
            // short-circuit by re-using `course.allItems`, but doing
            // our own walk here means we also pick up subtitle
            // files for videos that haven't been AVAsset-scanned
            // yet (and we don't need a duration for indexing).
            collectFiles(
                in: courseURL,
                courseKey: course.folderName,
                courseTitle: course.title,
                relativePrefix: "",
                out: &out
            )
        }
        return out
    }

    /// Recursive walk that yields one entry per indexable file
    /// (`.srt`/`.vtt`/`.html`/`.htm`) paired with the right
    /// `lesson_path` (the video path for subtitles, the file's own
    /// path for HTMLs).
    private func collectFiles(
        in directory: URL,
        courseKey: String,
        courseTitle: String,
        relativePrefix: String,
        out: inout [SearchIndexDatabase.FileOnDisk]
    ) {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            return
        }
        for entry in contents {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            let name = entry.lastPathComponent
            let relative = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
            if isDir {
                collectFiles(
                    in: entry,
                    courseKey: courseKey,
                    courseTitle: courseTitle,
                    relativePrefix: relative,
                    out: &out
                )
                continue
            }
            let mtime = mtimeSeconds(for: entry)
            if SubtitleIndexer.canIndex(entry) {
                // Pair the subtitle to a video. If we can't find one,
                // we still index using the subtitle's own path so the
                // content is searchable, but the tap will land on the
                // subtitle file (not ideal, but the data isn't lost).
                let videoPath = SubtitleIndexer.videoLessonPath(
                    for: relative,
                    videoExtensionsInOrder: ["mp4", "mov", "m4v", "webm"]
                ) ?? relative
                out.append(
                    SearchIndexDatabase.FileOnDisk(
                        courseKey: courseKey,
                        courseTitle: courseTitle,
                        lessonPath: videoPath,
                        kind: .subtitle,
                        mtime: mtime
                    )
                )
            } else if HtmlIndexer.canIndex(entry) {
                out.append(
                    SearchIndexDatabase.FileOnDisk(
                        courseKey: courseKey,
                        courseTitle: courseTitle,
                        lessonPath: relative,
                        kind: .html,
                        mtime: mtime
                    )
                )
            }
        }
    }

    /// Filesystem `mtime` as integer seconds since the epoch. We
    /// only need coarse precision (a second) because the FTS
    /// metadata also stores second resolution.
    private func mtimeSeconds(for url: URL) -> Int64 {
        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        if let date = attrs?[.modificationDate] as? Date {
            return Int64(date.timeIntervalSince1970.rounded())
        }
        return 0
    }

    // MARK: - Per-file indexing

    private func indexOneFile(
        file: SearchIndexDatabase.FileOnDisk,
        coursesRoot: URL
    ) async throws {
        // Resolve the on-disk URL of the file we need to read. For
        // subtitles the metadata says "the video path" but the bytes
        // to read are the subtitle's own file. We re-derive the
        // subtitle path by looking up the matching subtitle.
        let courseDir = coursesRoot.appendingPathComponent(file.courseKey, isDirectory: true)
        let fileURL: URL
        if file.kind == .subtitle {
            fileURL = try resolveSubtitleURL(
                forVideoLessonPath: file.lessonPath,
                coursesRoot: courseDir
            ) ?? courseDir
                .appendingPathComponent(file.lessonPath, isDirectory: false)
        } else {
            fileURL = courseDir
                .appendingPathComponent(file.lessonPath, isDirectory: false)
        }

        // Drop the old rows for this (course, lesson, kind) tuple
        // before inserting the new ones. A re-index is a replace,
        // not an append — otherwise a file that shrunk would leave
        // stale rows behind.
        try database.deleteAllForLesson(
            courseKey: file.courseKey,
            lessonPath: file.lessonPath,
            kind: file.kind
        )

        switch file.kind {
        case .subtitle:
            try await indexSubtitleFile(
                fileURL: fileURL,
                file: file
            )
        case .html:
            try await indexHtmlFile(
                fileURL: fileURL,
                file: file
            )
        }

        try database.recordMTime(
            courseKey: file.courseKey,
            lessonPath: file.lessonPath,
            kind: file.kind,
            mtime: file.mtime
        )
    }

    /// Find the subtitle file that matches a given video's
    /// `lesson_path`. The `lesson_path` we store for subtitles is
    /// the *video* path (e.g. `01 Intro/bienvenido.mp4`), but the
    /// bytes to read live in `01 Intro/bienvenido.srt` (or `.vtt`,
    /// or `.es.srt`, etc.). Try each candidate and return the first
    /// one that exists on disk.
    private func resolveSubtitleURL(
        forVideoLessonPath videoPath: String,
        coursesRoot: URL
    ) throws -> URL? {
        let videoNS = videoPath as NSString
        let dir = videoNS.deletingLastPathComponent
        let videoBasename = (videoNS.lastPathComponent as NSString).deletingPathExtension
        let videoDirURL: URL = {
            if dir.isEmpty {
                return coursesRoot
            }
            return coursesRoot.appendingPathComponent(dir, isDirectory: true)
        }()
        let languageSuffixes = ["", ".es", ".en", ".pt", ".fr", ".de", ".it", ".zh-Hans", ".zh-Hant", ".ja"]
        let extensions = ["srt", "vtt"]
        for ext in extensions {
            for suffix in languageSuffixes {
                let candidate = "\(videoBasename)\(suffix).\(ext)"
                let url = videoDirURL.appendingPathComponent(candidate, isDirectory: false)
                if fileManager.fileExists(atPath: url.path) {
                    return url
                }
            }
        }
        return nil
    }

    private func indexSubtitleFile(
        fileURL: URL,
        file: SearchIndexDatabase.FileOnDisk
    ) async throws {
        let cues = SubtitleIndexer.extract(from: fileURL)
        logger.notice("subtitle \(fileURL.lastPathComponent, privacy: .public): extracted \(cues.count) cue(s)")
        for cue in cues {
            try database.insert(
                courseKey: file.courseKey,
                courseTitle: file.courseTitle,
                lessonPath: file.lessonPath,
                kind: .subtitle,
                startSeconds: cue.startSeconds,
                paragraphIndex: nil,
                text: cue.text
            )
        }
    }

    private func indexHtmlFile(
        fileURL: URL,
        file: SearchIndexDatabase.FileOnDisk
    ) async throws {
        let blocks = HtmlIndexer.extractBlocks(from: fileURL)
        logger.notice("html \(fileURL.lastPathComponent, privacy: .public): extracted \(blocks.count) block(s)")
        for block in blocks {
            try database.insert(
                courseKey: file.courseKey,
                courseTitle: file.courseTitle,
                lessonPath: file.lessonPath,
                kind: .html,
                startSeconds: nil,
                paragraphIndex: block.index,
                text: block.text
            )
        }
    }
}
