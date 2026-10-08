// BrandColors.swift
//
// Color tokens for the cursosIpad chrome. Mirrors plan.md §14.1.1 (the
// "paleta SPID"). The two layers in the design coexist:
//
//   1. Chrome (this file) — fixed per theme. Navigation bars, tab bars,
//      menus, backgrounds, text. Gives the app its own identity
//      regardless of which course is on screen.
//   2. Course accent (CourseAccentColor) — derived per course from the
//      cover image. See CoverColorExtractor.swift.
//
// Implemented with `UIColor(dynamicProvider:)` so the same `Color` token
// automatically picks the right variant for the current
// `userInterfaceStyle`. No asset catalog needed — keeps the project
// simple and the tokens inspectable in code.

import SwiftUI
import UIKit

extension Color {
    /// Background of the app, background of cards. Light: pale blue.
    /// Dark: near-black with a blue tint to mirror the light value.
    static let appBackground = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x0E / 255, green: 0x11 / 255, blue: 0x19 / 255, alpha: 1)
            : UIColor(red: 0xED / 255, green: 0xF2 / 255, blue: 0xFA / 255, alpha: 1)
    })

    /// Navigation bars, tab bars, side menus. Always a deep navy, so the
    /// app feels "branded" even when a course uses a different accent.
    static let appMenu = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x0F / 255, green: 0x17 / 255, blue: 0x40 / 255, alpha: 1)
            : UIColor(red: 0x09 / 255, green: 0x18 / 255, blue: 0x4D / 255, alpha: 1)
    })

    /// Titles, primary text. Inverts with the background.
    static let appTitle = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0xED / 255, green: 0xF2 / 255, blue: 0xFA / 255, alpha: 1)
            : UIColor(red: 0x2F / 255, green: 0x2E / 255, blue: 0x2E / 255, alpha: 1)
    })

    /// Subtitles, captions, secondary metadata. Mid-gray that reads on
    /// both backgrounds.
    static let appInfo = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x9C / 255, green: 0xA0 / 255, blue: 0xAC / 255, alpha: 1)
            : UIColor(red: 0x80 / 255, green: 0x80 / 255, blue: 0x85 / 255, alpha: 1)
    })

    /// Hairline separators, card outlines. Subtle on either background.
    static let appDivider = Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 0x2A / 255, green: 0x2E / 255, blue: 0x3A / 255, alpha: 1)
            : UIColor(red: 0xD6 / 255, green: 0xDB / 255, blue: 0xE5 / 255, alpha: 1)
    })

    /// Fallback accent when we can't extract a usable color from a
    /// course's cover (white covers, missing cover, etc.). Plan §14.1.1
    /// fixes this as the brand purple — not the CTA color (that's the
    /// dynamic accent) but the secondary accent for chips, focus rings,
    /// and the fallback path.
    static let appAccentFallback = Color(
        red: 0x7B / 255,
        green: 0x5B / 255,
        blue: 0xF2 / 255
    )
}
