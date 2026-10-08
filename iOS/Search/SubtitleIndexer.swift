// SubtitleIndexer.swift
//
// Thin wrapper that dispatches to `SubtitleParser` based on the file
// extension. Lives between the orchestrator (`SearchIndexer`) and the
// pure parser (`SubtitleParser`) so the orchestrator doesn't have to
// care about format detection.
//
// Convention for matching a subtitle file to the video it belongs to
// (per the plan in `plan.md` §16.3 and §9):
//   `01 Intro/bienvenido.mp4` ← `01 Intro/bienvenido.srt`
//   `01 Intro/bienvenido.mp4` ← `01 Intro/bienvenido.es.srt`
//   `01 Intro/bienvenido.mp4` ← `01 Intro/bienvenido.vtt`
//   `01 Intro/bienvenido.mp4` ← `01 Intro/bienvenido.es.vtt`
//
// The language suffix is optional and ignored — the parser doesn't
// know about it; we strip it here when computing the matching
// basename. The suffix is `.` followed by 2–3 letters (ISO codes:
// `es`, `en`, `pt`, `zh-Hans` for the longer ones, etc.).
//
// This is a pure function over the filesystem: it does not touch the
// SQLite database. The caller passes the resulting cues to the
// database layer.

import Foundation

public enum SubtitleIndexer {

    /// Extensions we know how to index. The orchestrator uses this
    /// set to filter the filesystem walk.
    public static let supportedExtensions: Set<String> = ["srt", "vtt"]

    /// True if `url` points to a file we know how to index.
    public static func canIndex(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Read the file at `url` and return its cues. Dispatches to
    /// `SubtitleParser.parseSRT` or `SubtitleParser.parseVTT` based
    /// on the extension. Returns `[]` on read failure, parse failure,
    /// or unsupported extension — the orchestrator treats empty
    /// results as a no-op (the file might just be malformed, not
    /// worth failing the whole reindex).
    public static func extract(from url: URL) -> [SubtitleCue] {
        let ext = url.pathExtension.lowercased()
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return []
        }
        switch ext {
        case "srt":
            return SubtitleParser.parseSRT(data)
        case "vtt":
            return SubtitleParser.parseVTT(data)
        default:
            return []
        }
    }

    /// Returns the relative path of the video file that this subtitle
    /// file is paired with, given the original subtitle path. If no
    /// matching video exists, returns `nil`.
    ///
    /// Examples (with the original `relativePath` as input):
    ///   `"01 Intro/bienvenido.srt"`        → `"01 Intro/bienvenido.mp4"`
    ///   `"01 Intro/bienvenido.es.srt"`     → `"01 Intro/bienvenido.mp4"`
    ///   `"01 Intro/bienvenido.vtt"`        → `"01 Intro/bienvenido.mov"`
    ///
    /// This is used by the orchestrator to compute the `lesson_path`
    /// column for the FTS5 index, so taps on a subtitle result can
    /// resolve back to the video file in the curriculum.
    ///
    /// - Parameters:
    ///   - subtitleRelativePath: The path of the subtitle file,
    ///     relative to the course root (e.g. `"01 Intro/bienvenido.srt"`).
    ///   - videoExtensionsInOrder: The set of recognized video
    ///     extensions to try, in priority order (typically
    ///     `["mp4", "mov", "m4v", "webm"]`).
    public static func videoLessonPath(
        for subtitleRelativePath: String,
        videoExtensionsInOrder: [String]
    ) -> String? {
        // Split into directory + filename.
        let nsPath = subtitleRelativePath as NSString
        let directory = nsPath.deletingLastPathComponent
        let filename = nsPath.lastPathComponent
        let nsFilename = filename as NSString
        let rawBasename = nsFilename.deletingPathExtension // "bienvenido.es"

        // Strip an optional language suffix: ".es", ".en", ".zh-Hans".
        let basename = stripLanguageSuffix(rawBasename)

        let prefix: String
        if directory.isEmpty {
            prefix = basename
        } else {
            prefix = "\(directory)/\(basename)"
        }
        return videoExtensionsInOrder
            .map { "\(prefix).\($0)" }
            .first
    }

    /// Strip a trailing `.<lang>` suffix where `<lang>` is 2–3 letters,
    /// or a BCP-47-like tag with a hyphen (e.g. "zh-Hans", "pt-BR").
    /// Leaves the string untouched if no language suffix is found.
    private static func stripLanguageSuffix(_ basename: String) -> String {
        // Look for the last `.`; if what follows looks like a language
        // tag (letters and an optional hyphen + letters, 2–8 chars),
        // strip it.
        guard let lastDot = basename.lastIndex(of: ".") else { return basename }
        let suffix = basename[basename.index(after: lastDot)...]
        let pattern = #"^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return basename
        }
        let range = NSRange(suffix.startIndex..., in: suffix)
        if regex.firstMatch(in: String(suffix), range: range) != nil {
            return String(basename[..<lastDot])
        }
        return basename
    }
}
