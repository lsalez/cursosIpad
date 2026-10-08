// SearchPositionBanner.swift
//
// Banner shown on `CourseDetailView` when the user tapped a search
// result. Communicates the intended position ("min 12:34" /
// "párrafo 3") and is honest about the fact that the actual
// playback / scroll is not wired up yet (the video player ships in
// Fase 6, the HTML viewer in Fase 8).
//
// The banner sits between the hero and the tab picker, so it's
// visible regardless of which tab the user is on. Once the
// detail view consumes the position (in `onAppear`), it clears
// `pendingSearchPosition` so the same course opened normally
// later doesn't re-show the banner.

import Shared
import SwiftUI

struct SearchPositionBanner: View {
    let position: SearchPosition

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 22))
                .foregroundStyle(Color.appAccentFallback)
            VStack(alignment: .leading, spacing: 4) {
                Text(headline)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appTitle)
                Text(detail)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appInfo)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.appAccentFallback.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.appAccentFallback.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(headline). \(detail)")
    }

    private var headline: String {
        switch position {
        case let .subtitle(startSeconds, _, _):
            let minutes = Int(startSeconds) / 60
            let seconds = Int(startSeconds) % 60
            return "Empezar desde min \(String(format: "%d:%02d", minutes, seconds))"
        case let .html(paragraphIndex, _, _):
            return "Saltar al párrafo \(paragraphIndex)"
        }
    }

    private var detail: String {
        switch position {
        case .subtitle:
            return "Encontraste este momento buscando en los subtítulos. El reproductor con reanudar en posición llega en la Fase 6; por ahora la lección está marcada para que la encuentres rápido."
        case .html:
            return "Encontraste este párrafo buscando en los archivos HTML. El visor con scroll a párrafo llega en la Fase 8; por ahora la lección está marcada para que la encuentres rápido."
        }
    }
}

// MARK: - Preview-friendly formatting

extension SearchPosition {
    /// Human-readable label for the position, used by the banner
    /// and the search hit rows.
    var chipLabel: String {
        switch self {
        case let .subtitle(startSeconds, _, _):
            let minutes = Int(startSeconds) / 60
            let seconds = Int(startSeconds) % 60
            return "min \(String(format: "%d:%02d", minutes, seconds))"
        case let .html(paragraphIndex, _, _):
            return "párrafo \(paragraphIndex)"
        }
    }
}
