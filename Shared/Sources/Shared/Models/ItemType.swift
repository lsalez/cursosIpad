// ItemType.swift
//
// Source of truth for "what extensions we recognize" — referenced by
// `CourseIndexer` to filter filesystem entries and to classify them. Plan
// §9 has the canonical extension list; if we ever need to widen it,
// change the constants here once and the indexer picks it up.

import Foundation

public enum ItemType: String, Codable, CaseIterable, Sendable {
    case video
    case pdf
    case html

    /// Map a file extension (no leading `.`, case-insensitive) to an
    /// `ItemType`. Returns `nil` for extensions we don't recognize, so
    /// callers can filter with `compactMap`.
    public static func from(extension ext: String) -> ItemType? {
        switch ext.lowercased() {
        case "mp4", "mov", "m4v", "webm":
            return .video
        case "pdf":
            return .pdf
        case "html", "htm":
            return .html
        default:
            return nil
        }
    }

    /// Lowercase extensions (no dot) that get indexed, per plan §9.
    /// Anything outside this set is ignored by the indexer
    /// (`.DS_Store`, `.srt`, stray images, etc.).
    public static let recognizedExtensions: Set<String> = [
        // video
        "mp4", "mov", "m4v", "webm",
        // pdf
        "pdf",
        // html
        "html", "htm",
    ]

    /// Cover / thumbnail image extensions. Wider set than `recognizedExtensions`
    /// because covers never become `CourseItem`s — they're just files the
    /// indexer looks for explicitly.
    public static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "png", "heic",
    ]
}
