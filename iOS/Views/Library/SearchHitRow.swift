// SearchHitRow.swift
//
// One row in the search results list. Used for both subtitle and
// HTML hits — the only difference between them is the small chip on
// the right ("min 12:34" vs "párrafo 3") and the title line above
// the snippet. We factor that out into `SearchHitRow` so the result
// view can use a single type.
//
// Layout:
//   ┌────────────────────────────────────────────────────┐
//   │ [cover] Lección: Bienvenido                      [min 0:01]
//   │         …el patrón <<decorador>> en Python…        │
//   └────────────────────────────────────────────────────┘
//
// The cover is a 32×18 mini-thumbnail for the course (or a
// placeholder with the course's first letter if the cover can't
// load). The snippet's bold + accent color is produced by
// `SearchService.makeHighlightedSnippet(from:)` — we receive an
// `AttributedString` and render it as-is.

import Shared
import SwiftUI

struct SearchHitRow: View {
    let title: String
    let course: Course
    let store: LibraryStore
    let chip: String
    let snippet: AttributedString
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                coverThumb
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.appTitle)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    Text(snippet)
                        .font(.system(size: 13))
                        .foregroundStyle(Color.appInfo)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                chipView
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.appBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.appDivider.opacity(0.5), lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(chip)")
    }

    // MARK: - Subviews

    private var coverThumb: some View {
        ZStack {
            if let image = coverLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                let tint = store.coverColor(for: course)
                LinearGradient(
                    colors: [tint.opacity(0.85), tint.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text(initial)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                )
            }
        }
        .frame(width: 48, height: 27)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private var chipView: some View {
        Text(chip)
            .font(.system(size: 11, weight: .medium, design: .rounded))
            .foregroundStyle(Color.appMenu)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.appMenu.opacity(0.08))
            )
            .fixedSize()
    }

    private var initial: String {
        let trimmed = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first).uppercased()
    }

    // MARK: - Cover loading

    @StateObject private var coverLoader: CoverImageLoader

    init(
        title: String,
        course: Course,
        store: LibraryStore,
        chip: String,
        snippet: AttributedString,
        onTap: @escaping () -> Void
    ) {
        self.title = title
        self.course = course
        self.store = store
        self.chip = chip
        self.snippet = snippet
        self.onTap = onTap
        _coverLoader = StateObject(wrappedValue: CoverImageLoader(url: store.coverURL(for: course)))
    }
}
