// DetailTab.swift
//
// Tabs inside the course detail screen. Plan §14.5 specifies three:
// Contenido (curriculum, the default), Descripción, Archivos. On
// iPhone they're rendered as a segmented control. On iPad the right
// column of the detail split view also uses the same segmented
// control (so the same enum drives both layouts).

import Foundation

enum DetailTab: String, CaseIterable, Identifiable {
    case content
    case description
    case files

    var id: String { rawValue }

    var title: String {
        switch self {
        case .content: return "Contenido"
        case .description: return "Descripción"
        case .files: return "Archivos"
        }
    }
}
