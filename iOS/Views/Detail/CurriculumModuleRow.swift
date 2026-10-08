// CurriculumModuleRow.swift
//
// One module in the curriculum, with a collapsible list of lessons.
// Plan §14.5 says:
//
//   * "Acordeón de módulos, todos expandidos por defecto."
//   * "Cabecera de módulo: nombre + palomita si todas las lecciones
//      están completas."
//
// We keep a `Binding<Bool>` per row so the parent (the curriculum
// list) can override the default-expanded behavior if it ever needs
// to. For Fase 3 we start everyone expanded and the binding is just
// driven by local `@State`.

import Shared
import SwiftUI

struct CurriculumModuleRow: View {
    let module: Module
    let accent: Color
    let lastViewedItemID: UUID?
    let highlightedItemID: UUID?
    let courseDirectory: URL?
    let onTapLesson: (CourseItem) -> Void

    @State private var isExpanded: Bool = true

    init(
        module: Module,
        accent: Color,
        lastViewedItemID: UUID? = nil,
        highlightedItemID: UUID? = nil,
        courseDirectory: URL? = nil,
        onTapLesson: @escaping (CourseItem) -> Void
    ) {
        self.module = module
        self.accent = accent
        self.lastViewedItemID = lastViewedItemID
        self.highlightedItemID = highlightedItemID
        self.courseDirectory = courseDirectory
        self.onTapLesson = onTapLesson
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isExpanded {
                VStack(spacing: 0) {
                    Divider()
                        .background(Color.appDivider.opacity(0.5))
                    VStack(spacing: 0) {
                        ForEach(Array(module.items.enumerated()), id: \.element.id) { _, item in
                            CurriculumLessonRow(
                                item: item,
                                isLastViewed: item.id == lastViewedItemID,
                                isHighlighted: item.id == highlightedItemID,
                                accent: accent,
                                courseDirectory: courseDirectory,
                                onTap: { onTapLesson(item) }
                            )
                            if item.id != module.items.last?.id {
                                Divider()
                                    .background(Color.appDivider.opacity(0.4))
                            }
                        }
                    }
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

    // MARK: - Header

    private var header: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.18)) {
                isExpanded.toggle()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appInfo)
                    .frame(width: 16)
                Text(module.title)
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appTitle)
                    .lineLimit(1)
                Spacer(minLength: 8)
                if module.isFullyCompleted {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(accent)
                } else {
                    Text("\(module.items.count)")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.appInfo)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(module.title)
        .accessibilityValue("\(module.items.count) lecciones\(module.isFullyCompleted ? ", completo" : "")")
    }
}
