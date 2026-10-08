// SubtitleCue.swift
//
// A single subtitle entry extracted from an SRT or VTT file. Mirrors
// the shape used by the parser (`SubtitleParser`) and the indexer
// (`SubtitleIndexer`); the search layer writes one row per cue to
// the SQLite FTS5 table.
//
// `index` mirrors the 1-based numbering used in SRT files. VTT often
// omits it, in which case the parser assigns a sequential value, so
// callers can always rely on `index` being present and ordered.
//
// `endSeconds` is optional because VTT allows cues without an end
// timestamp (open-ended cues). The search layer ignores `endSeconds`
// for now — we only need the start time to drive the "min 12:34"
// chip in the result row. The field is kept on the model for future
// use (e.g. highlighting the active cue while the video plays).
//
// `text` is always normalized to a single line: internal newlines and
// runs of whitespace are collapsed to a single space, and the string
// is trimmed. This keeps the FTS5 tokens consistent and avoids
// fragmenting a single cue across multiple rows.

import Foundation

public struct SubtitleCue: Equatable, Sendable, Hashable {
    public let index: Int
    public let startSeconds: Double
    public let endSeconds: Double?
    public let text: String

    public init(
        index: Int,
        startSeconds: Double,
        endSeconds: Double?,
        text: String
    ) {
        self.index = index
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.text = text
    }
}
