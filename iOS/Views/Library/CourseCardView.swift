// CourseCardView.swift
//
// Single course card used in the iOS library grid. Plan §14.4 specs:
//   - Cover 16:9 with 12pt rounded corners (placeholder if missing).
//   - Title (2 lines, truncated).
//   - Thin progress bar + "X de Y lecciones • Z%".
//   - Micro-badge "Continuar ▶" if the course has a last-viewed item.
//
// The card is intentionally a dumb view: it takes a `Course` and a
// `LibraryStore` (for the cover URL / dominant color) and renders.
// Navigation / taps are the parent's responsibility (Fase 3 wires the
// detail view; for now a tap is a no-op).

import Shared
import SwiftUI

struct CourseCardView: View {
    let course: Course
    let store: LibraryStore

    @StateObject private var coverLoader: CoverImageLoader

    init(course: Course, store: LibraryStore) {
        self.course = course
        self.store = store
        _coverLoader = StateObject(wrappedValue: CoverImageLoader(url: store.coverURL(for: course)))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cover
            titleAndMeta
            progress
        }
        .padding(10)
        .background(Color.appBackground)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.appDivider.opacity(0.5), lineWidth: 0.5)
        )
    }

    // MARK: - Cover

    private var cover: some View {
        ZStack(alignment: .bottomTrailing) {
            coverImage
                .frame(maxWidth: .infinity)
                .aspectRatio(16.0 / 9.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let lastViewedItem = lastViewedItem {
                ContinueBadge(text: lastViewedItem.title)
                    .padding(8)
            }
        }
    }

    @ViewBuilder
    private var coverImage: some View {
        if let image = coverLoader.image {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
        } else {
            // Placeholder: initial on a gradient derived from the
            // course's dominant color (or the brand fallback).
            let tint = store.coverColor(for: course)
            LinearGradient(
                colors: [tint.opacity(0.85), tint.opacity(0.55)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                Text(initial)
                    .font(.system(size: 44, weight: .bold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.9))
            )
        }
    }

    private var initial: String {
        let trimmed = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first).uppercased()
    }

    // MARK: - Title + meta

    private var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(course.title)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.appTitle)
                .lineLimit(2)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if !course.tags.isEmpty {
                Text(course.tags.prefix(3).joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInfo)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Progress

    private var progress: some View {
        let total = course.totalItemCount
        let completed = course.allItems.filter(\.progress.isCompleted).count
        let percent = total > 0 ? Int((Double(completed) / Double(total) * 100).rounded()) : 0
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: course.totalProgress)
                .progressViewStyle(.linear)
                .tint(store.coverColor(for: course))
            Text("\(completed) de \(total) lecciones · \(percent)%")
                .font(.system(size: 11))
                .foregroundStyle(Color.appInfo)
        }
    }

    // MARK: - Last viewed (for the badge)

    private var lastViewedItem: CourseItem? {
        let candidates = course.allItems.compactMap { item -> (Date, CourseItem)? in
            guard let date = item.progress.lastViewedAt else { return nil }
            return (date, item)
        }
        return candidates.max(by: { $0.0 < $1.0 })?.1
    }
}

// MARK: - Continue badge

private struct ContinueBadge: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 9, weight: .bold))
            Text("Continuar")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(.black.opacity(0.55))
        )
    }
}
