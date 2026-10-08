// SearchResultsView.swift
//
// The three-section results screen shown in the library when the
// user has typed something in the search bar. Sections:
//
//   1. **Cursos** — name matches. Uses the existing `CourseCardView`
//      so the visual is consistent with the main grid.
//   2. **Subtítulos** — up to ~10 subtitle hits, each rendered as
//      a `SearchHitRow` with a "min 12:34" chip.
//   3. **HTMLs** — same shape, with a "párrafo N" chip.
//
// The view is intentionally a `LazyVStack` inside a `ScrollView` so
// the library's existing scrollable container continues to work
// without nesting `List` inside `ScrollView` (which breaks the
// safe-area insets in iOS 17+).
//
// Tap routing is the parent's responsibility: this view exposes
// three callbacks (`onSelectCourse`, `onSelectSubtitle`,
// `onSelectHtml`) so the parent decides whether to push, split, or
// scroll.

import Shared
import SwiftUI

struct SearchResultsView: View {
    let results: SearchResults
    let store: LibraryStore
    let onSelectCourse: (Course) -> Void
    let onSelectSubtitle: (SubtitleHit) -> Void
    let onSelectHtml: (HtmlHit) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if !results.courses.isEmpty {
                sectionHeader(title: "Cursos", count: results.courses.count)
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(results.courses) { course in
                        Button {
                            onSelectCourse(course)
                        } label: {
                            CourseCardView(course: course, store: store)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !results.subtitles.isEmpty {
                sectionHeader(title: "Subtítulos", count: results.subtitles.count)
                VStack(spacing: 8) {
                    ForEach(results.subtitles) { hit in
                        SearchHitRow(
                            title: hit.itemTitle,
                            course: hit.course,
                            store: store,
                            chip: "min \(formatTimestamp(hit.startSeconds))",
                            snippet: hit.snippet,
                            onTap: { onSelectSubtitle(hit) }
                        )
                    }
                }
            }

            if !results.htmls.isEmpty {
                sectionHeader(title: "HTMLs", count: results.htmls.count)
                VStack(spacing: 8) {
                    ForEach(results.htmls) { hit in
                        SearchHitRow(
                            title: hit.itemTitle,
                            course: hit.course,
                            store: store,
                            chip: "párrafo \(hit.paragraphIndex)",
                            snippet: hit.snippet,
                            onTap: { onSelectHtml(hit) }
                        )
                    }
                }
            }
        }
    }

    // MARK: - Section header

    private func sectionHeader(title: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appTitle)
            Text("(\(count))")
                .font(.system(size: 13))
                .foregroundStyle(Color.appInfo)
            Spacer(minLength: 0)
        }
        .padding(.top, 4)
    }

    // MARK: - Timestamp formatting

    private func formatTimestamp(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
