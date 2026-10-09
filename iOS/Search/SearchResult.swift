// SearchResult.swift
//
// Data types for the search subsystem. Three layers:
//
//   1. `SearchIndexDatabase.SearchHit` (defined inside the DB layer)
//      — what comes back from a raw SQLite query. Includes the raw
//      `snippet()` string with `<<`/`>>` delimiters around the
//      match, the FTS5 rank, and the natural course key.
//
//   2. The hit types defined here — `SubtitleHit` and `HtmlHit` —
//      add the UI-friendly shape: a resolved `Course` (not just the
//      key), an `AttributedString` snippet with the match bolded,
//      and the human-readable title and timestamp for the row.
//
//   3. `SearchResults` — the bundle returned by `SearchService` to
//      the library view. Wraps the name matches, the subtitle hits,
//      and the HTML hits.
//
// `SearchPosition` is the contract for "tap on a result → jump to a
// specific position in a specific lesson". The video player (Fase 6)
// and HTML viewer (Fase 8) consume this when they land. For Fase 4
// the `CourseDetailView` reads it just to display a banner with the
// intended position.

import Foundation
import Shared
import SwiftUI

// MARK: - Bundle of search results

public struct SearchResults: Equatable, Sendable {
    public var courses: [Course]
    public var lessons: [LessonHit]
    public var subtitles: [SubtitleHit]
    public var htmls: [HtmlHit]

    public init(
        courses: [Course] = [],
        lessons: [LessonHit] = [],
        subtitles: [SubtitleHit] = [],
        htmls: [HtmlHit] = []
    ) {
        self.courses = courses
        self.lessons = lessons
        self.subtitles = subtitles
        self.htmls = htmls
    }

    public static let empty = SearchResults()

    public var isEmpty: Bool {
        courses.isEmpty && lessons.isEmpty && subtitles.isEmpty && htmls.isEmpty
    }
}

// MARK: - Hit types

/// A lesson whose **title** matched the query. Computed in-memory
/// from `Course.allItems` alongside the course name match — no FTS5
/// involved, because the indexer only seeds subtitle/HTML content,
/// not file names. Snippet is the lesson title with the matched
/// substring bolded and accented.
public struct LessonHit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let course: Course
    public let itemRelativePath: String
    public let itemTitle: String
    public let itemTypeRaw: String
    public let snippet: AttributedString

    public init(
        id: UUID = UUID(),
        course: Course,
        itemRelativePath: String,
        itemTitle: String,
        itemTypeRaw: String,
        snippet: AttributedString
    ) {
        self.id = id
        self.course = course
        self.itemRelativePath = itemRelativePath
        self.itemTitle = itemTitle
        self.itemTypeRaw = itemTypeRaw
        self.snippet = snippet
    }
}

public struct SubtitleHit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let course: Course
    public let itemRelativePath: String
    public let itemTitle: String
    public let startSeconds: Double
    public let snippet: AttributedString

    public init(
        id: UUID = UUID(),
        course: Course,
        itemRelativePath: String,
        itemTitle: String,
        startSeconds: Double,
        snippet: AttributedString
    ) {
        self.id = id
        self.course = course
        self.itemRelativePath = itemRelativePath
        self.itemTitle = itemTitle
        self.startSeconds = startSeconds
        self.snippet = snippet
    }
}

public struct HtmlHit: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let course: Course
    public let itemRelativePath: String
    public let itemTitle: String
    public let paragraphIndex: Int
    public let snippet: AttributedString

    public init(
        id: UUID = UUID(),
        course: Course,
        itemRelativePath: String,
        itemTitle: String,
        paragraphIndex: Int,
        snippet: AttributedString
    ) {
        self.id = id
        self.course = course
        self.itemRelativePath = itemRelativePath
        self.itemTitle = itemTitle
        self.paragraphIndex = paragraphIndex
        self.snippet = snippet
    }
}

// MARK: - Position contract

/// The intended playback/scroll position for a search hit. Consumed
/// by the future visors (Fase 6/8) and by the `CourseDetailView` for
/// Fase 4 to display a banner explaining where the user would land.
public enum SearchPosition: Equatable, Sendable {
    /// Resume a video at the given second. `itemRelativePath` is
    /// the relative path of the video file (the lesson, not the
    /// subtitle). `courseID` is the `Course.id` so the detail view
    /// can match it to the right course.
    case subtitle(startSeconds: Double, itemRelativePath: String, courseID: UUID)
    /// Scroll an HTML viewer to the given 1-based paragraph index.
    case html(paragraphIndex: Int, itemRelativePath: String, courseID: UUID)
}
