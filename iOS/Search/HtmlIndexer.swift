// HtmlIndexer.swift
//
// Extracts plain-text "blocks" from an HTML file so the FTS5 index
// can search them. A block is roughly a paragraph: a run of text
// delimited by blank lines. The block number (1-based) is what we
// surface as "párrafo N" in the search results.
//
// The hard part of indexing HTML is preserving the paragraph
// structure. We therefore **pre-process** the HTML source: every
// closing block tag (`</p>`, `<br>`, `<br/>`, `</li>`,
// `</h1>`..`</h6>`, `</div>`, `</section>`) is rewritten to a `\n\n`
// pair, all remaining tags are stripped, and common entities are
// decoded. The result is plain text whose paragraphs are separated by
// blank lines, which we split on `\n{2,}` to recover the blocks.
//
// We deliberately do **not** route the result through
// `NSAttributedString(html:)`: that parser treats its input as HTML
// and collapses all whitespace, destroying the blank-line structure
// we just built (and it would only be a main-thread-only detour).
//
// **Tolerated failures:** unreadable file, empty content. All return
// `[]`.

import Foundation

public enum HtmlIndexer {

    /// Extensions the orchestrator considers indexable. Symmetric
    /// with `ItemType.recognizedExtensions.html` in the Shared
    /// package, but stated here as a `Set<String>` for the
    /// filesystem walker.
    public static let supportedExtensions: Set<String> = ["html", "htm"]

    /// True if `url` points to a file we know how to index.
    public static func canIndex(_ url: URL) -> Bool {
        supportedExtensions.contains(url.pathExtension.lowercased())
    }

    /// Read the HTML at `url` and split it into paragraph blocks.
    /// Returns `[]` for unreadable, empty, or unparseable files.
    /// Each tuple is `(index: 1-based, text: trimmed text)`.
    public static func extractBlocks(from url: URL) -> [(index: Int, text: String)] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            return []
        }
        let raw = decodeText(data)
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return []
        }
        let preprocessed = preprocessHTML(raw)
        return splitBlocks(preprocessed)
    }

    // MARK: - Pre-processing

    /// Replace closing block-level tags with `\n\n` so the paragraph
    /// structure survives the `NSAttributedString` parse. We also
    /// strip `<script>` and `<style>` blocks entirely (their content
    /// is noise for the search index).
    static func preprocessHTML(_ html: String) -> String {
        var working = html

        // Drop <script>...</script> and <style>...</style> blocks.
        working = stripBlocks(named: "script", in: working)
        working = stripBlocks(named: "style", in: working)
        // Drop HTML comments.
        working = stripHTMLComments(working)

        // Replace each known closing block tag with a paragraph break.
        // The list mirrors what a typical slide-deck-style HTML page
        // uses; if we miss a tag, the resulting block boundaries
        // shift but the search still works.
        let blockClosers = [
            "</p>", "</div>", "</section>", "</article>", "</header>",
            "</footer>", "</main>", "</aside>", "</blockquote>",
            "</pre>", "</figure>", "</figcaption>",
        ]
        for tag in blockClosers {
            working = working.replacingOccurrences(of: tag, with: "\n\n", options: .caseInsensitive)
        }
        // Self-closing line breaks.
        for tag in ["<br>", "<br/>", "<br />"] {
            working = working.replacingOccurrences(of: tag, with: "\n\n", options: .caseInsensitive)
        }
        // <li> opens and closes with bullets; we want one block per
        // list item, so replace the closing tag with a paragraph
        // break and leave the opening tag as-is (it gets stripped
        // below).
        working = working.replacingOccurrences(of: "</li>", with: "\n\n", options: .caseInsensitive)
        // Heading closers too — each heading is its own block.
        for n in 1...6 {
            working = working.replacingOccurrences(of: "</h\(n)>", with: "\n\n", options: .caseInsensitive)
        }

        // Strip any remaining tags. We don't try to be smart about
        // `<a href>` — the text content is what matters for search,
        // the URL is noise. Greedy `<.*?>` removal is good enough.
        working = stripAllTags(working)

        // Decode the most common HTML entities. `NSAttributedString`
        // would do this for us, but doing it once here is cheaper
        // than letting it happen via the parser on a full document
        // and is harmless if the input is already plain text.
        working = decodeBasicEntities(working)

        return working
    }

    /// Drop every `<name ...>...</name>` block. Matches across
    /// newlines (`[\s\S]*?`) so multi-line scripts are caught.
    private static func stripBlocks(named name: String, in html: String) -> String {
        let pattern = "<\(name)\\b[^>]*>[\\s\\S]*?</\(name)\\s*>"
        guard let regex = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive]
        ) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(
            in: html,
            range: range,
            withTemplate: ""
        )
    }

    /// Drop `<!-- ... -->` comments.
    private static func stripHTMLComments(_ html: String) -> String {
        let pattern = "<!--[\\s\\S]*?-->"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    /// Drop every remaining `<...>` tag, including their attributes.
    /// Greedy dotall on the smallest possible run.
    private static func stripAllTags(_ html: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "<[^>]+>") else { return html }
        let range = NSRange(html.startIndex..., in: html)
        return regex.stringByReplacingMatches(in: html, range: range, withTemplate: "")
    }

    /// Decode the entities we encounter most often in real-world
    /// slides & notes. Anything else is left as-is; FTS5's tokenizer
    /// will still match the underlying letters.
    private static func decodeBasicEntities(_ text: String) -> String {
        let pairs: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
        ]
        var output = text
        for (entity, replacement) in pairs {
            output = output.replacingOccurrences(of: entity, with: replacement)
        }
        return output
    }

    // MARK: - Block splitting

    /// Split the preprocessed plain text into paragraph blocks. Each
    /// block is a run of text between blank lines. Empty or
    /// whitespace-only blocks are dropped. Whitespace inside a block
    /// is collapsed to a single space and the result is trimmed.
    static func splitBlocks(_ text: String) -> [(index: Int, text: String)] {
        // Normalize line endings and split on blank-line runs.
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        // A paragraph break is a run of two or more newlines, possibly
        // padded with spaces/tabs (e.g. `"\n   \n"`). Collapse every
        // such run to a single `"\n\n"` so the subsequent split is
        // exact.
        let blankRun = try? NSRegularExpression(pattern: "\\n(?:[ \\t]*\\n)+")
        let normalizedBreaks: String
        if let blankRun {
            let range = NSRange(normalized.startIndex..., in: normalized)
            normalizedBreaks = blankRun.stringByReplacingMatches(
                in: normalized,
                range: range,
                withTemplate: "\n\n"
            )
        } else {
            normalizedBreaks = normalized
        }
        let blocks = normalizedBreaks
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        var out: [(index: Int, text: String)] = []
        out.reserveCapacity(blocks.count)
        for (i, block) in blocks.enumerated() {
            // Collapse internal whitespace runs to a single space.
            let collapsed = block
                .split(whereSeparator: { $0.isWhitespace })
                .joined(separator: " ")
            if collapsed.isEmpty { continue }
            out.append((index: i + 1, text: collapsed))
        }
        return out
    }

    // MARK: - Text decoding

    /// Decode bytes as UTF-8, stripping a leading BOM if present.
    /// Falls back to lossy UTF-8 if the bytes aren't valid UTF-8.
    private static func decodeText(_ data: Data) -> String {
        let utf8: String
        if let strict = String(data: data, encoding: .utf8) {
            utf8 = strict
        } else {
            utf8 = String(decoding: data, as: UTF8.self)
        }
        if utf8.hasPrefix("\u{FEFF}") {
            return String(utf8.dropFirst())
        }
        return utf8
    }
}
