// SubtitleParser.swift
//
// Pure parsers for SRT and VTT subtitle files. Lives in the iOS
// target (not `Shared/`) because the macOS app doesn't index
// subtitles for Fase 4. If/when the Mac editor grows a "preview
// subtitles" feature, these can be promoted to the shared package.
//
// The parsers are deliberately tolerant of the common drift between
// format variants seen in the wild:
//   * UTF-8 BOM at the start of the file (some Windows exporters
//     add one, some don't).
//   * SRT cues without a numeric index (legal per the SRT spec but
//     rarely seen in practice).
//   * VTT files where the first non-empty line is `WEBVTT` optionally
//     followed by a header (`WEBVTT - Some Title`).
//   * VTT `NOTE` blocks (single- or multi-line) which must be
//     skipped.
//   * VTT cues without an end timestamp (`00:00:01.000 -->` with
//     nothing after the arrow) — `endSeconds` is set to `nil`.
//   * Both `,` and `.` as the decimal separator in timestamps
//     (SRT uses `,`, VTT uses `.`).
//   * Multi-line cue text — joined into a single line with spaces.
//   * Windows line endings (`\r\n`) mixed in with Unix line endings.
//
// The parsers never throw. Files that are unparseable, empty, or in
// an unsupported encoding return `[]`. A single malformed cue does
// not abort the rest of the file — it is skipped.

import Foundation

public enum SubtitleParser {

    // MARK: - SRT

    /// Parse a SubRip (`.srt`) file. Returns an array of cues, ordered
    /// as they appear in the file. Returns `[]` for empty/invalid input.
    public static func parseSRT(_ data: Data) -> [SubtitleCue] {
        let text = decodeText(data)
        return parseBlocks(
            text,
            headerLinesToSkip: 0,
            acceptCueIndex: true,
            acceptEndTimestamp: true
        )
    }

    // MARK: - VTT

    /// Parse a WebVTT (`.vtt`) file. Returns an array of cues. Returns
    /// `[]` for empty/invalid input. Strips the `WEBVTT` header line
    /// and any `NOTE` blocks before parsing the rest as cues.
    public static func parseVTT(_ data: Data) -> [SubtitleCue] {
        let text = decodeText(data)
        // Normalize line endings so we can split on a single char.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
        var kept: [String] = []
        var skippingNote = false
        for raw in lines {
            let line = String(raw)
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("WEBVTT") {
                // Drop the header line; the optional metadata on the
                // same line is also dropped (we never use it).
                continue
            }
            if trimmed.hasPrefix("NOTE") {
                // A NOTE block runs until the next blank line. The
                // `NOTE` keyword itself is sometimes on its own line
                // and sometimes followed by inline text.
                skippingNote = true
                continue
            }
            if trimmed.isEmpty {
                skippingNote = false
                kept.append(line)
                continue
            }
            if skippingNote {
                continue
            }
            kept.append(line)
        }
        let body = kept.joined(separator: "\n")
        return parseBlocks(
            body,
            headerLinesToSkip: 0,
            acceptCueIndex: false,
            acceptEndTimestamp: true
        )
    }

    // MARK: - Shared block parser

    /// Split the text into cues by blank-line separators, then parse
    /// each block. `acceptCueIndex` controls whether the optional
    /// leading line in each block (SRT's "1", "2", ...) is expected.
    private static func parseBlocks(
        _ text: String,
        headerLinesToSkip: Int,
        acceptCueIndex: Bool,
        acceptEndTimestamp: Bool
    ) -> [SubtitleCue] {
        // Normalize line endings: split on \n, \r\n, or \r.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        let blocks = normalized
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var cues: [SubtitleCue] = []
        var fallbackIndex = 1
        for block in blocks {
            let blockLines = block
                .components(separatedBy: "\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !blockLines.isEmpty else { continue }

            // Find the timestamp line. Tolerate an optional leading
            // index line (SRT). Skip styles/regions for VTT.
            var timestampIndex: Int?
            for (i, line) in blockLines.enumerated() {
                if line.contains("-->") {
                    timestampIndex = i
                    break
                }
            }
            guard let tsIndex = timestampIndex else { continue }

            let timestampLine = blockLines[tsIndex]
            guard let (start, end) = parseTimestampLine(
                timestampLine,
                acceptEnd: acceptEndTimestamp
            ) else { continue }

            // Identify an explicit cue index, if present, on the line
            // immediately above the timestamp. We accept it as a
            // string of digits only; otherwise we ignore it.
            let explicitIndex: Int? = {
                if !acceptCueIndex { return nil }
                if tsIndex == 0 { return nil }
                let candidate = blockLines[tsIndex - 1]
                if candidate.allSatisfy(\.isNumber), let value = Int(candidate) {
                    return value
                }
                return nil
            }()

            // Cue text is everything after the timestamp line. Join
            // multi-line cues into a single space-separated line.
            let textLines = Array(blockLines[(tsIndex + 1)...])
            let joined = textLines.joined(separator: " ")
            let collapsed = collapseWhitespace(joined)
            guard !collapsed.isEmpty else { continue }

            let cue = SubtitleCue(
                index: explicitIndex ?? fallbackIndex,
                startSeconds: start,
                endSeconds: end,
                text: collapsed
            )
            cues.append(cue)
            fallbackIndex += 1
        }
        return cues
    }

    // MARK: - Timestamp helpers

    /// Parse a single timeline line like
    /// `00:00:01,000 --> 00:00:04,000` (SRT) or
    /// `00:00:01.000 --> 00:00:04.000 align:start position:10%` (VTT
    /// with cue settings). Returns the start and optional end
    /// timestamps in seconds. `nil` end when the line ends right
    /// after the arrow (VTT open-ended cues).
    private static func parseTimestampLine(
        _ line: String,
        acceptEnd: Bool
    ) -> (Double, Double?)? {
        // Split on the arrow; ignore anything after the end timestamp
        // (VTT cue settings like "align:start" are valid but we don't
        // need them).
        let parts = line.components(separatedBy: "-->")
        guard parts.count >= 1 else { return nil }
        guard let start = parseTimestamp(String(parts[0])) else { return nil }
        guard acceptEnd, parts.count >= 2 else { return (start, nil) }
        // The end timestamp may be followed by whitespace + cue
        // settings; the timestamp itself is the first whitespace-
        // delimited token of the second half.
        let endHalf = String(parts[1])
        let endToken = endHalf.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true).first
        guard let endToken else { return (start, nil) }
        guard let end = parseTimestamp(String(endToken)) else { return (start, nil) }
        return (start, end)
    }

    /// Parse an `HH:MM:SS,mmm` or `MM:SS.mmm` timestamp into seconds.
    /// Tolerates both `,` and `.` as the millisecond separator.
    private static func parseTimestamp(_ raw: String) -> Double? {
        // First try the canonical HH:MM:SS,mmm format. We don't try
        // MM:SS.mmm separately because the regex is permissive and
        // accepts it too: with HH = 0.
        let cleaned = raw.trimmingCharacters(in: .whitespaces)
        let pattern = #"^(?:(\d{1,2}):)?(\d{1,2}):(\d{1,2})[.,](\d{1,3})$"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return nil
        }
        let range = NSRange(cleaned.startIndex..., in: cleaned)
        guard let match = regex.firstMatch(in: cleaned, range: range),
              match.numberOfRanges == 5 else {
            return nil
        }
        func capture(_ index: Int) -> String? {
            guard let r = Range(match.range(at: index), in: cleaned) else {
                return nil
            }
            return String(cleaned[r])
        }
        let hours = Int(capture(1) ?? "0") ?? 0
        let minutes = Int(capture(2) ?? "") ?? 0
        let seconds = Int(capture(3) ?? "") ?? 0
        let millisString = capture(4) ?? "0"
        // Pad/truncate to 3 digits so "5" → 500ms, "50" → 500ms
        // would be wrong but "050" would be 50ms; we treat any
        // missing precision as fractional milliseconds.
        let millis: Int
        if millisString.count == 3 {
            millis = Int(millisString) ?? 0
        } else if millisString.count == 2 {
            millis = (Int(millisString) ?? 0) * 10
        } else if millisString.count == 1 {
            millis = (Int(millisString) ?? 0) * 100
        } else {
            millis = 0
        }
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(millis) / 1000.0
    }

    // MARK: - Text helpers

    /// Decode the bytes as UTF-8, stripping a leading BOM if present.
    /// Falls back to lossy UTF-8 if the bytes are not valid UTF-8.
    private static func decodeText(_ data: Data) -> String {
        let utf8: String
        if let strict = String(data: data, encoding: .utf8) {
            utf8 = strict
        } else {
            utf8 = String(decoding: data, as: UTF8.self)
        }
        // Strip a UTF-8 BOM if present. The character is U+FEFF; it
        // is not a printable character, so we never want to index it.
        if utf8.hasPrefix("\u{FEFF}") {
            return String(utf8.dropFirst())
        }
        return utf8
    }

    /// Collapse runs of whitespace (including newlines) into a single
    /// space. Trims the ends.
    private static func collapseWhitespace(_ text: String) -> String {
        let pieces = text.split(whereSeparator: { $0.isWhitespace })
        return pieces.joined(separator: " ")
    }
}
