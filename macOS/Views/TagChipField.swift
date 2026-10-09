// TagChipField.swift
//
// Mail-style chip input for editing a course's `tags`. A horizontal
// row of `Capsule` chips on the left, a text field on the right
// that commits a new chip on `Enter`, `,`, `;`, or `Tab`.
//
// Pure leaf control: takes `@Binding [String]` and a focus binding
// for auto-commit on blur. Doesn't import `Shared`, doesn't know
// about `Course`. The parent view (the Mac editor) owns the
// binding to `course.tags` and the hydrate/dirty/save loop that
// gates writes to the sidecar.
//
// Visual style mirrors the iOS chip at
// `iOS/Views/Library/LibraryView.swift:399-400` — same `Color.appMenu`
// token, same `Capsule(style: .continuous)` shape, same 11pt
// rounded design. Inactive chips are the muted variant so they
// don't compete with the editor's primary controls.

import SwiftUI

struct TagChipField: View {
    @Binding var tags: [String]
    var placeholder: String = "Agrega una etiqueta…"
    var onSubmit: (() -> Void)?

    /// Buffer for the in-progress tag the user is typing. Resets
    /// when a chip is committed or when the parent clears `tags`.
    @State private var draft: String = ""
    /// Tracks whether the embedded `TextField` is focused, so the
    /// parent can `onChange` blur events if it wants.
    @FocusState private var fieldFocused: Bool

    var body: some View {
        // Wrapping flow so a course with many tags doesn't push the
        // text field off-screen — the chips wrap to the next line
        // and the input always sits at the end of the last row.
        FlowLayout(spacing: 6, lineSpacing: 6) {
            ForEach(tags.indices, id: \.self) { index in
                chip(for: tags[index], at: index)
            }
            inputField
        }
    }

    // MARK: - Chip

    @ViewBuilder
    private func chip(for tag: String, at index: Int) -> some View {
        HStack(spacing: 4) {
            Text(tag)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.appMenu)
            Button {
                remove(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.appMenu.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Quitar etiqueta")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.appMenu.opacity(0.10))
        )
    }

    // MARK: - Input

    private var inputField: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .regular, design: .rounded))
            .frame(minWidth: 120)
            .focused($fieldFocused)
            .onSubmit { commit() }
            .onChange(of: draft) { _, newValue in
                // Auto-commit on comma / semicolon. Lets the user
                // type "python,backend" and get two chips out of
                // one text field. Trim whitespace around the
                // separator.
                if let separator = newValue.first(where: { $0 == "," || $0 == ";" }),
                   let splitIndex = newValue.firstIndex(of: separator) {
                    let before = String(newValue[..<splitIndex])
                    let after = String(newValue[newValue.index(after: splitIndex)...])
                    draft = before
                    commit()
                    draft = after
                }
            }
    }

    // MARK: - Mutators

    private func commit() {
        let trimmed = draft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        // Avoid duplicates (case-insensitive, matching macOS
        // filesystem convention; otherwise "Python" and "python"
        // would be two chips).
        let lower = trimmed.lowercased()
        if !tags.contains(where: { $0.lowercased() == lower }) {
            tags.append(trimmed)
        }
        draft = ""
        onSubmit?()
    }

    private func remove(at index: Int) {
        guard tags.indices.contains(index) else { return }
        tags.remove(at: index)
    }
}

// MARK: - Flow layout

/// Lightweight flow layout: lays out children left-to-right and
/// wraps to the next line when the horizontal space is exhausted.
/// Used so a course with many tags wraps instead of pushing the
/// text field off-screen. SwiftUI's `LazyVGrid` would also work
/// but its row count isn't dynamic, which makes the "always
/// trailing text field" pattern awkward.
private struct FlowLayout: Layout {
    var spacing: CGFloat = 4
    var lineSpacing: CGFloat = 4

    func sizeThatFits(
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let lines = computeLines(maxWidth: maxWidth, subviews: subviews)
        let height = lines.reduce(CGFloat(0)) { partial, line in
            partial + line.maxHeight
        } + CGFloat(max(0, lines.count - 1)) * lineSpacing
        return CGSize(
            width: lines.map(\.totalWidth).max() ?? 0,
            height: height
        )
    }

    func placeSubviews(
        in bounds: CGRect,
        proposal: ProposedViewSize,
        subviews: Subviews,
        cache: inout ()
    ) {
        let lines = computeLines(maxWidth: bounds.width, subviews: subviews)
        var y = bounds.minY
        for line in lines {
            var x = bounds.minX
            for item in line.items {
                let size = subviews[item.index].sizeThatFits(.unspecified)
                subviews[item.index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(size)
                )
                x += size.width + spacing
            }
            y += line.maxHeight + lineSpacing
        }
    }

    // MARK: - Layout helpers

    private struct Item {
        let index: Int
        let width: CGFloat
    }

    private struct Line {
        var items: [Item] = []
        var totalWidth: CGFloat = 0
        var maxHeight: CGFloat = 0
    }

    private func computeLines(maxWidth: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let proposed = Item(index: index, width: size.width)
            var current = lines[lines.count - 1]
            let needsNewLine = current.items.count > 0
                && current.totalWidth + size.width + spacing > maxWidth
            if needsNewLine {
                lines.append(Line())
                current = lines[lines.count - 1]
            }
            current.items.append(proposed)
            current.totalWidth += (current.items.count > 1 ? spacing : 0) + size.width
            current.maxHeight = max(current.maxHeight, size.height)
            lines[lines.count - 1] = current
        }
        return lines
    }
}
