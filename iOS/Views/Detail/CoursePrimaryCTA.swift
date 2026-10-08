// CoursePrimaryCTA.swift
//
// The big primary action button on the course detail hero. Plan §14.5
// specifies three variants based on progress:
//
//   1. "Continuar aprendiendo: <última lección> ▶" — when any item
//      has a `lastViewedAt`, jump back to that item.
//   2. "Empezar curso ▶" — when the course is at 0%, open the first
//      item of the first non-empty module.
//   3. "Continuar viendo ▶" — fallback for "has progress but no
//      lastViewedAt", a state that shouldn't really happen but is
//      handled gracefully anyway.
//
// The button background is the course's cover-derived accent, with the
// theme-adjusted variant (lighter in dark, darker in light — see
// `CourseAccentColor.swift`).
//
// Tapping the button doesn't actually navigate to a viewer yet — the
// visors live in Fases 6/7/8. For Fase 3 the action closes over the
// lesson the CTA points at and surfaces a "Próximamente" alert naming
// the target lesson and which phase implements it. The same alert
// pattern is used by `LibraryView` for "Recibir por WiFi" (Fase 11),
// so users see consistent copy.

import Shared
import SwiftUI

struct CoursePrimaryCTA: View {
    let course: Course
    let store: LibraryStore
    let accent: Color
    let onOpenLesson: (CourseItem) -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text(label)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                Image(systemName: "play.fill")
                    .font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(accent)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityHint("Abre la lección actual del curso.")
    }

    // MARK: - Label + action

    private var label: String {
        if let last = lastViewedItem {
            return "Continuar aprendiendo: \(last.title)"
        }
        if course.totalProgress == 0 {
            return "Empezar curso"
        }
        return "Continuar viendo"
    }

    private var lastViewedItem: CourseItem? {
        let candidates = course.allItems.compactMap { item -> (Date, CourseItem)? in
            guard let date = item.progress.lastViewedAt else { return nil }
            return (date, item)
        }
        return candidates.max(by: { $0.0 < $1.0 })?.1
    }

    private var targetItem: CourseItem? {
        if let last = lastViewedItem { return last }
        for module in course.modules {
            if let first = module.items.first { return first }
        }
        return nil
    }

    private func action() {
        if let target = targetItem {
            onOpenLesson(target)
        }
    }
}
