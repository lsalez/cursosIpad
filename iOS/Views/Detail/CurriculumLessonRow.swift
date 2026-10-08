// CurriculumLessonRow.swift
//
// A single lesson inside the curriculum (Tab Contenido). Plan §14.5:
//
//   * Video  → mini 16:9 thumbnail (Fase 6 adds auto-generated
//              thumbnails; for now we render a placeholder with a
//              play icon) + title + duration "12:34" + checkmark if
//              completed. Highlighted if it's the last viewed item.
//   * PDF    → type icon + title + checkmark.
//   * HTML   → type icon + title + checkmark.
//
// The row is a plain button — tapping calls `onTap` with the lesson.
// The parent wires that to "open the viewer" (Fases 6/7/8); for Fase
// 3 the parent shows a "Próximamente" alert.

import Shared
import SwiftUI

struct CurriculumLessonRow: View {
    let item: CourseItem
    let isLastViewed: Bool
    let isHighlighted: Bool
    let accent: Color
    let courseDirectory: URL?
    let onTap: () -> Void

    /// Lazily resolves the video thumbnail via `VideoThumbnailLoader`.
    /// Only present for video items — PDF / HTML rows skip the loader
    /// entirely. Held in `@State` so the loader instance is stable
    /// across re-renders of the same row (`ForEach(module.items)` uses
    /// `id: \.element.id`, see `CurriculumModuleRow`).
    @State private var thumbnailLoader: VideoThumbnailLoader?

    init(
        item: CourseItem,
        isLastViewed: Bool = false,
        isHighlighted: Bool = false,
        accent: Color,
        courseDirectory: URL? = nil,
        onTap: @escaping () -> Void
    ) {
        self.item = item
        self.isLastViewed = isLastViewed
        self.isHighlighted = isHighlighted
        self.accent = accent
        self.courseDirectory = courseDirectory
        self.onTap = onTap
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                leading
                Spacer(minLength: 0)
                title
                trailing
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 10)
            .background(rowBackground)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .task { ensureThumbnailLoader() }
        .onDisappear { thumbnailLoader?.cancel() }
    }

    /// Lazily sets up `thumbnailLoader` the first time the row appears
    /// (and only if it's a video with a known course directory).
    /// `@State` initialization at the `@State` declaration site is the
    /// idiomatic SwiftUI pattern, but we don't have all inputs at
    /// `init` time because SwiftUI calls `init` before the parent
    /// environment stabilizes; this deferred form is safer.
    private func ensureThumbnailLoader() {
        guard item.type == .video,
              thumbnailLoader == nil,
              let courseDirectory else { return }
        thumbnailLoader = VideoThumbnailLoader(
            item: item,
            courseDirectory: courseDirectory,
            durationSeconds: item.durationSeconds
        )
        thumbnailLoader?.start()
    }

    // MARK: - Leading visual

    @ViewBuilder
    private var leading: some View {
        switch item.type {
        case .video:
            videoThumb
                .frame(width: 80, height: 45)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .pdf, .html:
            typeIcon
                .frame(width: 36, height: 36)
        }
    }

    private var videoThumb: some View {
        ZStack {
            // Background: either the resolved thumbnail, or the
            // accent-tinted gradient placeholder. We never show a
            // partial blur or a broken image — placeholder until the
            // loader resolves.
            if let image = thumbnailLoader?.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: [accent.opacity(0.6), accent.opacity(0.3)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                Image(systemName: "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
    }

    private var typeIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Color.appMenu.opacity(0.08))
            Image(systemName: iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(Color.appMenu)
        }
    }

    private var iconName: String {
        switch item.type {
        case .pdf: return "doc.richtext"
        case .html: return "globe"
        case .video: return "play.rectangle"
        }
    }

    // MARK: - Title + meta

    private var title: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(item.title)
                .font(.system(size: 14, weight: .medium, design: .rounded))
                .foregroundStyle(Color.appTitle)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
            if let meta = secondaryMeta {
                Text(meta)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInfo)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Subtitle line under the title: duration for videos, file type
    /// label for PDFs/HTMLs.
    private var secondaryMeta: String? {
        switch item.type {
        case .video:
            guard let duration = item.durationSeconds, duration > 0 else { return nil }
            return Self.formatDuration(duration)
        case .pdf:
            return "PDF"
        case .html:
            return "HTML"
        }
    }

    private static func formatDuration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Trailing (checkmark if completed)

    private var trailing: some View {
        Group {
            if item.progress.isCompleted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(accent)
            } else {
                Image(systemName: "circle")
                    .font(.system(size: 18))
                    .foregroundStyle(Color.appDivider)
            }
        }
    }

    // MARK: - Row background (highlight if last viewed or search target)

    @ViewBuilder
    private var rowBackground: some View {
        if isLastViewed {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(accent.opacity(0.10))
        } else if isHighlighted {
            // Search hit: stronger highlight in the brand purple,
            // distinct from the per-course accent.
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.appAccentFallback.opacity(0.16))
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Color.appAccentFallback.opacity(0.4), lineWidth: 0.5)
                )
        } else {
            Color.clear
        }
    }

    // MARK: - Accessibility

    private var accessibilityLabel: String {
        var parts: [String] = [item.title]
        if let meta = secondaryMeta { parts.append(meta) }
        if item.progress.isCompleted { parts.append("completada") }
        if isLastViewed { parts.append("vista por última vez") }
        return parts.joined(separator: ", ")
    }
}
