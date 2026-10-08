// CourseHeroView.swift
//
// The "course landing" header at the top of `CourseDetailView`. Plan
// §14.5 specifies, in order:
//
//   * Cover 16:9 full-width.
//   * Title (large, bold).
//   * Tag chips (if any) and a short meta line ("N lecciones ·
//     HH:MM de video").
//   * Primary CTA (`CoursePrimaryCTA`) with the dynamic cover-derived
//     accent.
//   * Progress bar + "X de Y lecciones • Z% completado".
//   * Secondary text button: "Marcar curso como completado".
//
// The hero also exposes `markCompletedTapped` so the parent view can
// run the actual sidecar/state mutation (Fase 5 persists; for now
// `LibraryStore` mutates the in-memory `Course`).
//
// iPad split: the hero is meant to live in the *left* column of the
// detail's internal split (40% of the width). The view itself doesn't
// know that — it just lays out vertically with sensible defaults —
// and the parent composes it inside a 40%-wide column on iPad.

import Shared
import SwiftUI

struct CourseHeroView: View {
    let course: Course
    let store: LibraryStore
    let accent: Color
    let onOpenLesson: (CourseItem) -> Void
    let onMarkCompleted: () -> Void

    @StateObject private var coverLoader: CoverImageLoader

    init(
        course: Course,
        store: LibraryStore,
        accent: Color,
        onOpenLesson: @escaping (CourseItem) -> Void,
        onMarkCompleted: @escaping () -> Void
    ) {
        self.course = course
        self.store = store
        self.accent = accent
        self.onOpenLesson = onOpenLesson
        self.onMarkCompleted = onMarkCompleted
        _coverLoader = StateObject(
            wrappedValue: CoverImageLoader(url: store.coverURL(for: course))
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            cover
            titleAndMeta
            CoursePrimaryCTA(
                course: course,
                store: store,
                accent: accent,
                onOpenLesson: onOpenLesson
            )
            progressSection
            markCompletedButton
        }
    }

    // MARK: - Cover

    private var cover: some View {
        Group {
            if let image = coverLoader.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.85), accent.opacity(0.55)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    Text(initial)
                        .font(.system(size: 72, weight: .bold, design: .rounded))
                        .foregroundStyle(.white.opacity(0.9))
                )
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(16.0 / 9.0, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Title + meta

    private var titleAndMeta: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(course.title)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(Color.appTitle)
                .lineLimit(3)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if !course.tags.isEmpty {
                TagsRow(tags: course.tags)
            }

            Text(metaLine)
                .font(.system(size: 13))
                .foregroundStyle(Color.appInfo)
        }
    }

    private var metaLine: String {
        let lessonCount = course.totalItemCount
        let totalSeconds = course.allItems
            .compactMap(\.durationSeconds)
            .reduce(0, +)
        let durationString = Self.formatDuration(totalSeconds)
        let lessonLabel = lessonCount == 1 ? "lección" : "lecciones"
        return "\(lessonCount) \(lessonLabel)" + (durationString.map { " · \($0) de video" } ?? "")
    }

    private static func formatDuration(_ seconds: Double) -> String? {
        guard seconds > 0 else { return nil }
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Progress section

    private var progressSection: some View {
        let total = course.totalItemCount
        let completed = course.allItems.filter(\.progress.isCompleted).count
        let percent = total > 0
            ? Int((course.totalProgress * 100).rounded())
            : 0
        return VStack(alignment: .leading, spacing: 4) {
            ProgressView(value: course.totalProgress)
                .progressViewStyle(.linear)
                .tint(accent)
            Text("\(completed) de \(total) lecciones · \(percent)% completado")
                .font(.system(size: 12))
                .foregroundStyle(Color.appInfo)
        }
    }

    // MARK: - Mark completed

    private var markCompletedButton: some View {
        Button(action: onMarkCompleted) {
            Text("Marcar curso como completado")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .disabled(course.totalProgress >= 1.0)
        .accessibilityHint("Marca todas las lecciones del curso como vistas.")
    }

    // MARK: - Initial (for the placeholder cover)

    private var initial: String {
        let trimmed = course.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return "·" }
        return String(first).uppercased()
    }
}

// MARK: - Tags

private struct TagsRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.appMenu.opacity(0.08))
                        )
                        .foregroundStyle(Color.appMenu)
                }
            }
        }
    }
}
