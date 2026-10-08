// CurriculumView.swift
//
// Tab "Contenido" — the curriculum. Stack of `CurriculumModuleRow`,
// one per module in the course. Plan §14.5 specifies the
// expandable accordion layout with checkmarks per module.
//
// Tap on a lesson fires `onTapLesson(item)`. The parent
// (`CourseDetailView`) is responsible for routing the tap to the
// right viewer (or, for Fase 3, a "Próximamente" alert).
//
// `highlightedItemID` is the optional `CourseItem.id` to draw with
// the search-hit background — used when the user got here by
// tapping a subtitle/HTML search result.

import Shared
import SwiftUI

struct CurriculumView: View {
    let course: Course
    let accent: Color
    let highlightedItemID: UUID?
    let onTapLesson: (CourseItem) -> Void

    init(
        course: Course,
        accent: Color,
        highlightedItemID: UUID? = nil,
        onTapLesson: @escaping (CourseItem) -> Void
    ) {
        self.course = course
        self.accent = accent
        self.highlightedItemID = highlightedItemID
        self.onTapLesson = onTapLesson
    }

    var body: some View {
        if course.modules.isEmpty {
            emptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(course.modules) { module in
                    CurriculumModuleRow(
                        module: module,
                        accent: accent,
                        lastViewedItemID: lastViewedItemID,
                        highlightedItemID: highlightedItemID,
                        onTapLesson: onTapLesson
                    )
                }
            }
        }
    }

    // MARK: - Helpers

    /// The `id` of the item with the most recent `lastViewedAt`. Used
    /// by the module row to highlight that lesson in the list.
    private var lastViewedItemID: UUID? {
        let candidates = course.allItems.compactMap { item -> (Date, UUID)? in
            guard let date = item.progress.lastViewedAt else { return nil }
            return (date, item.id)
        }
        return candidates.max(by: { $0.0 < $1.0 })?.1
    }

    private var emptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "tray")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Este curso no tiene contenido todavía.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
