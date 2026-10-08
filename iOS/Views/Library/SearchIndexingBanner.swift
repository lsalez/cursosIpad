// SearchIndexingBanner.swift
//
// Compact "Indexando 35 %" pill shown at the top of the library
// while the FTS5 reindex is running. Lives in the library view
// above the search results (or the grid, during the very first
// refresh). Designed to be subtle: the search works in the
// background, the user shouldn't be pestered by it.

import SwiftUI

struct SearchIndexingBanner: View {
    /// Reindex progress in `0.0...1.0`. `nil` means "running, no
    /// percentage known yet" (the first progress event is always
    /// `(0, N)` so the percentage is `0`; we treat `0/0` as
    /// indeterminate by convention).
    let progress: Double?

    var body: some View {
        HStack(spacing: 10) {
            ProgressView()
                .controlSize(.small)
                .tint(Color.appMenu)
            Text(label)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(Color.appInfo)
            Spacer(minLength: 0)
            if let progress, progress > 0 {
                Text("\(Int((progress * 100).rounded()))%")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appMenu)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.appMenu.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.appDivider.opacity(0.4), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel(label)
    }

    private var label: String {
        if let progress, progress > 0 {
            return "Indexando contenido…"
        }
        return "Indexando contenido…"
    }
}
