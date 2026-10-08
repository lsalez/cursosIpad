// CourseFilesView.swift
//
// Tab "Archivos" — a flat list of every file in the course (no
// module grouping). Per plan §14.5, this view is meant for the
// "find a specific file" use case where the curriculum's nested
// structure gets in the way.
//
// Each row reuses the visual language of `CurriculumLessonRow` so a
// file looks the same in both tabs. Same tap-to-open semantics.

import Shared
import SwiftUI

struct CourseFilesView: View {
    let course: Course
    let accent: Color
    let onTapItem: (CourseItem) -> Void

    var body: some View {
        if course.allItems.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                Text("\(course.allItems.count) archivos en este curso")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appInfo)
                VStack(spacing: 0) {
                    ForEach(Array(course.allItems.enumerated()), id: \.element.id) { index, item in
                        FileRow(
                            item: item,
                            accent: accent,
                            onTap: { onTapItem(item) }
                        )
                        if index < course.allItems.count - 1 {
                            Divider()
                                .background(Color.appDivider.opacity(0.4))
                        }
                    }
                }
                .background(Color.appBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.appDivider.opacity(0.5), lineWidth: 0.5)
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Este curso no tiene archivos todavía.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}

/// One file in the flat list. Reuses the same `CurriculumLessonRow`
/// visuals so the two tabs feel like the same screen.
private struct FileRow: View {
    let item: CourseItem
    let accent: Color
    let onTap: () -> Void

    var body: some View {
        // `CurriculumLessonRow` is unstyled enough to work here too:
        // it just shows the leading visual + title + checkmark. The
        // `isLastViewed` highlight is irrelevant in the flat list, so
        // we pass `false`.
        CurriculumLessonRow(
            item: item,
            isLastViewed: false,
            accent: accent,
            onTap: onTap
        )
    }
}
