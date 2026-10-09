// SearchService.swift
//
// UI-facing facade for the search subsystem. Owned by `LibraryStore`
// and read by the library / detail views via `@EnvironmentObject`.
//
// What this layer adds on top of `SearchIndexer`:
//
//   * **Main-actor isolation** — `@Published` properties require
//     `@MainActor`, and SwiftUI views expect to read them on the
//     main thread. The actor that drives the database can't hold
//     these directly, so we sit in between.
//
//   * **Debouncing.** The library's `.searchable` fires on every
//     keystroke. Running an FTS5 query for every keystroke is
//     wasteful and produces flicker. We wait 200 ms of quiet before
//     dispatching a query, and we cancel the previous pending
//     query when a new one comes in.
//
//   * **Snippet rendering.** The raw `<<`/`>>`-delimited snippet
//     that comes back from SQLite is not view-ready. We translate
//     it to an `AttributedString` with the match in bold and
//     accent-colored.
//
//   * **Hit enrichment.** A `SearchHit` carries a `courseKey` (a
//     folder name) and a `lessonPath` (a string), but the UI wants
//     a resolved `Course` and a `CourseItem` (or at least its
//     `title` and `type`). We do that lookup here, falling back to
//     the title derived from the lesson path when the item is
//     missing (e.g. the file disappeared between index and query).
//
//   * **Name matching.** The "Cursos" section of the result view is
//     a simple in-memory `localizedCaseInsensitiveContains` over
//     course titles — no FTS5 needed. We compute it alongside the
//     FTS query so the bundle is ready in one update.

import Foundation
import Shared
import SwiftUI

@MainActor
public final class SearchService: ObservableObject {

    // MARK: - Published state

    @Published public private(set) var results: SearchResults = .empty
    @Published public private(set) var isIndexing: Bool = false
    @Published public private(set) var indexProgress: Double? = nil

    // MARK: - Dependencies

    private let indexer: SearchIndexer
    private let fileManager: FileManager
    private let coursesRoot: URL

    // MARK: - Task handles

    private var queryTask: Task<Void, Never>?
    private var reindexTask: Task<Void, Never>?
    private var progressTask: Task<Void, Never>?

    // MARK: - Init

    public init(
        indexer: SearchIndexer,
        fileManager: FileManager = .default,
        coursesRoot: URL
    ) {
        self.indexer = indexer
        self.fileManager = fileManager
        self.coursesRoot = coursesRoot
        // Start listening to progress right away. The reindex may
        // start before this finishes — that's fine, we just won't
        // see the very first events.
        progressTask = Task { [weak self] in
            guard let self else { return }
            await self.observeProgress()
        }
    }

    deinit {
        queryTask?.cancel()
        reindexTask?.cancel()
        progressTask?.cancel()
    }

    // MARK: - Reindex

    /// Trigger a reindex based on the latest course snapshot.
    /// Cancels any in-flight reindex. Called from
    /// `LibraryStore.refresh()` after the main indexer has run.
    public func startReindex(courses: [Course]) {
        reindexTask?.cancel()
        isIndexing = true
        indexProgress = nil
        let indexerRef = self.indexer
        let root = self.coursesRoot
        reindexTask = Task.detached(priority: .utility) { [weak self] in
            guard self != nil else { return }
            await indexerRef.reindex(courses: courses, coursesRoot: root)
        }
    }

    /// Run the search indexer on the latest snapshot. If a reindex
    /// was already running, this cancels it first (the startReindex
    /// path already handles that, but this is here for the
    /// "explicit" case where the UI knows it just changed the data).
    public func cancelReindex() {
        reindexTask?.cancel()
        reindexTask = nil
        isIndexing = false
        indexProgress = nil
    }

    // MARK: - Query

    /// Run a debounced full-text query. `rawQuery` is the literal
    /// text the user has typed; we split on whitespace, drop empty
    /// tokens, and join with FTS5-friendly AND semantics (each
    /// token becomes a `term*` prefix match, which is what users
    /// expect when typing partial words).
    ///
    /// Cancels any in-flight query before starting a new one, and
    /// also clears results when the query is empty.
    public func search(_ rawQuery: String, courses: [Course]) {
        let trimmed = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        queryTask?.cancel()
        guard !trimmed.isEmpty else {
            results = .empty
            return
        }
        // Name matches are computed synchronously and updated
        // immediately so the "Cursos" and "Lecciones" sections don't
        // lag. The indexer only seeds subtitle/HTML content into
        // FTS5, so lesson titles (which often differ from any
        // indexed content) need their own in-memory pass.
        let nameMatches = courses.filter { course in
            course.title.localizedCaseInsensitiveContains(trimmed)
        }
        let lessonMatches = Self.makeLessonHits(courses: courses, query: trimmed)
        results = SearchResults(
            courses: nameMatches,
            lessons: lessonMatches,
            subtitles: results.subtitles,
            htmls: results.htmls
        )
        queryTask = Task { [weak self] in
            // Debounce 200 ms.
            try? await Task.sleep(nanoseconds: 200_000_000)
            if Task.isCancelled { return }
            guard let self else { return }
            await self.runFTSQuery(rawQuery: trimmed, courses: courses)
        }
    }

    /// Clear the results and cancel any in-flight query. Called when
    /// the user empties the search field.
    public func clear() {
        queryTask?.cancel()
        queryTask = nil
        results = .empty
    }

    // MARK: - FTS query body

    private func runFTSQuery(rawQuery: String, courses: [Course]) async {
        let ftsQuery = buildFTSQuery(from: rawQuery)
        guard !ftsQuery.isEmpty else {
            results = SearchResults(
                courses: results.courses,
                lessons: results.lessons
            )
            return
        }
        do {
            let hits = try await indexer.search(query: ftsQuery, limit: 50)
            if Task.isCancelled { return }
            // Convert raw hits into the UI-ready shape, joining
            // back with the courses we already know about.
            let (subtitles, htmls) = enrich(hits: hits, courses: courses)
            results = SearchResults(
                courses: results.courses,
                lessons: results.lessons,
                subtitles: subtitles,
                htmls: htmls
            )
        } catch {
            print("[SearchService] FTS query failed: \(error)")
            // On error, keep the courses and lessons matches but
            // drop the FTS results. The user can re-type to retry.
            results = SearchResults(
                courses: results.courses,
                lessons: results.lessons,
                subtitles: [],
                htmls: []
            )
        }
    }

    /// Convert a free-form string like "decorador python" into a
    /// safe FTS5 prefix expression. Each token becomes `token*` so
    /// partial words match; special characters that FTS5 would
    /// interpret as operators are stripped.
    private func buildFTSQuery(from raw: String) -> String {
        let tokens = raw
            .lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .punctuationCharacters) }
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    // MARK: - Lesson title match

    /// Walk the course snapshot and return a `LessonHit` for every
    /// item whose title contains `query` (case-insensitive). This
    /// runs synchronously alongside the course-name match, so the
    /// "Lecciones" section lights up the moment the user types —
    /// no FTS5 debounce.
    ///
    /// Cost is `O(sum of allItems)` per call. For a typical iPad
    /// library (low hundreds of items) this is sub-millisecond, so
    /// we don't bother indexing titles into the FTS5 database; the
    /// title is already in the in-memory `Course` snapshot the
    /// indexer built on its filesystem walk.
    private static func makeLessonHits(
        courses: [Course],
        query: String
    ) -> [LessonHit] {
        guard !query.isEmpty else { return [] }
        var hits: [LessonHit] = []
        for course in courses {
            for item in course.allItems {
                guard item.title.localizedCaseInsensitiveContains(query) else {
                    continue
                }
                hits.append(
                    LessonHit(
                        course: course,
                        itemRelativePath: item.relativePath,
                        itemTitle: item.title,
                        itemTypeRaw: item.type.rawValue,
                        snippet: makeHighlightedTitle(item.title, query: query)
                    )
                )
            }
        }
        return hits
    }

    /// Build an `AttributedString` of `text` with the first
    /// case-insensitive occurrence of `query` bolded and accented.
    /// Used for the lesson-title section, where we don't have the
    /// FTS5 `<<`/`>>` delimiter pipeline that the subtitle/HTML
    /// snippets use.
    public static func makeHighlightedTitle(
        _ text: String,
        query: String
    ) -> AttributedString {
        var attributed = AttributedString(text)
        guard !query.isEmpty,
              let attrRange = attributed.range(
                of: query,
                options: .caseInsensitive
              )
        else {
            return attributed
        }
        attributed[attrRange].font = .body.bold()
        attributed[attrRange].foregroundColor = .accentColor
        return attributed
    }

    // MARK: - Hit enrichment

    private func enrich(
        hits: [SearchIndexDatabase.SearchHit],
        courses: [Course]
    ) -> (subtitles: [SubtitleHit], htmls: [HtmlHit]) {
        let courseByKey = Dictionary(uniqueKeysWithValues: courses.map { ($0.folderName, $0) })
        var subtitles: [SubtitleHit] = []
        var htmls: [HtmlHit] = []
        for hit in hits {
            guard let course = courseByKey[hit.courseKey] else {
                // Course was deleted between index and query;
                // skip rather than show a phantom.
                continue
            }
            let title = titleForHit(hit: hit, course: course)
            let snippet = Self.makeHighlightedSnippet(from: hit.snippetRaw)
            switch hit.kind {
            case .subtitle:
                guard let start = hit.startSeconds else { continue }
                subtitles.append(
                    SubtitleHit(
                        course: course,
                        itemRelativePath: hit.lessonPath,
                        itemTitle: title,
                        startSeconds: start,
                        snippet: snippet
                    )
                )
            case .html:
                guard let paragraph = hit.paragraphIndex else { continue }
                htmls.append(
                    HtmlHit(
                        course: course,
                        itemRelativePath: hit.lessonPath,
                        itemTitle: title,
                        paragraphIndex: paragraph,
                        snippet: snippet
                    )
                )
            }
        }
        return (subtitles, htmls)
    }

    /// Derive a human-readable title for a search hit. Prefer the
    /// `CourseItem.title` (which already strips extensions and
    /// replaces underscores with spaces, etc.) when we can find a
    /// matching item in the course; fall back to the filename
    /// without extension.
    private func titleForHit(
        hit: SearchIndexDatabase.SearchHit,
        course: Course
    ) -> String {
        if let item = course.allItems.first(where: { $0.relativePath == hit.lessonPath }) {
            return item.title
        }
        let filename = (hit.lessonPath as NSString).lastPathComponent
        return (filename as NSString).deletingPathExtension
    }

    /// Convert FTS5's `<<`/`>>`-delimited snippet to a styled
    /// `AttributedString` with the match in bold + accent color.
    /// Runs that are not inside delimiters are appended verbatim.
    public static func makeHighlightedSnippet(from raw: String) -> AttributedString {
        var result = AttributedString()
        var cursor = raw.startIndex
        while cursor < raw.endIndex {
            if let open = raw.range(of: "<<", range: cursor..<raw.endIndex),
               let close = raw.range(of: ">>", range: open.upperBound..<raw.endIndex) {
                let prefix = raw[cursor..<open.lowerBound]
                if !prefix.isEmpty {
                    result.append(AttributedString(String(prefix)))
                }
                let matchText = raw[open.upperBound..<close.lowerBound]
                var highlighted = AttributedString(String(matchText))
                highlighted.font = .body.bold()
                highlighted.foregroundColor = .accentColor
                result.append(highlighted)
                cursor = close.upperBound
            } else {
                let tail = raw[cursor..<raw.endIndex]
                if !tail.isEmpty {
                    result.append(AttributedString(String(tail)))
                }
                break
            }
        }
        return result
    }

    // MARK: - Progress observation

    private func observeProgress() async {
        let stream = await indexer.progressUpdates
        for await progress in stream {
            self.isIndexing = progress.total > 0 && progress.processed < progress.total
            self.indexProgress = progress.fraction
            if !self.isIndexing {
                // Clear after a short delay so the user sees the
                // "100 %" state before the banner disappears.
                // Actually, just clear immediately — the user
                // typically doesn't watch the percentage.
            }
        }
    }
}
