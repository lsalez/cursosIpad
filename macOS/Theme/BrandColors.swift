// BrandColors.swift
//
// macOS-side mirror of the iOS palette tokens (`iOS/Theme/BrandColors.swift`).
// Plan §14.1.1 calls for two layers that the chrome uses everywhere:
//
//   1. Fixed per theme (this file) — backgrounds, navigation bars, tab bars,
//      titles, info text, dividers. Gives the app its own identity
//      independent of which course is on screen.
//   2. Per-course accent (CourseAccentColor.swift, macOS-side) — derived
//      from the cover image.
//
// The iOS version is implemented with `UIColor(dynamicProvider:)`, which is
// UIKit-only. On macOS, the matching primitive is
// `NSColor(name:dynamicProvider:)` — when the dynamic provider hands back a
// different RGB pair based on `NSAppearance.bestMatch(from:)` we get the
// same per-theme behavior the iOS file gets from UITraitCollection. We then
// bridge the resulting `NSColor` to SwiftUI's `Color`.
//
// The hex values are copied verbatim from `iOS/Theme/BrandColors.swift` and
// from plan §14.1.1 — if we ever change one side, change the other too.

import AppKit
import SwiftUI

extension Color {
    /// Background of the app, background of cards. Light: pale blue.
    /// Dark: near-black with a blue tint to mirror the light value.
    static let appBackground: Color = Color(
        nsColor: NSColor(name: "appBackground") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0x0E / 255, green: 0x11 / 255, blue: 0x19 / 255, alpha: 1)
                : NSColor(red: 0xED / 255, green: 0xF2 / 255, blue: 0xFA / 255, alpha: 1)
        }
    )

    /// Navigation bars, tab bars, side menus. Always a deep navy, so the
    /// app feels "branded" even when a course uses a different accent.
    static let appMenu: Color = Color(
        nsColor: NSColor(name: "appMenu") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0x0F / 255, green: 0x17 / 255, blue: 0x40 / 255, alpha: 1)
                : NSColor(red: 0x09 / 255, green: 0x18 / 255, blue: 0x4D / 255, alpha: 1)
        }
    )

    /// Titles, primary text. Inverts with the background.
    static let appTitle: Color = Color(
        nsColor: NSColor(name: "appTitle") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0xED / 255, green: 0xF2 / 255, blue: 0xFA / 255, alpha: 1)
                : NSColor(red: 0x2F / 255, green: 0x2E / 255, blue: 0x2E / 255, alpha: 1)
        }
    )

    /// Subtitles, captions, secondary metadata. Mid-gray that reads on
    /// both backgrounds.
    static let appInfo: Color = Color(
        nsColor: NSColor(name: "appInfo") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0x9C / 255, green: 0xA0 / 255, blue: 0xAC / 255, alpha: 1)
                : NSColor(red: 0x80 / 255, green: 0x80 / 255, blue: 0x85 / 255, alpha: 1)
        }
    )

    /// Hairline separators, card outlines. Subtle on either background.
    static let appDivider: Color = Color(
        nsColor: NSColor(name: "appDivider") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
                ? NSColor(red: 0x2A / 255, green: 0x2E / 255, blue: 0x3A / 255, alpha: 1)
                : NSColor(red: 0xD6 / 255, green: 0xDB / 255, blue: 0xE5 / 255, alpha: 1)
        }
    )

    /// Fallback accent when we can't extract a usable color from a
    /// course's cover (white covers, missing cover, etc.). Plan §14.1.1
    /// fixes this as the brand purple — used for chips, focus rings,
    /// and the fallback path on the Mac too.
    static let appAccentFallback = Color(
        red: 0x7B / 255,
        green: 0x5B / 255,
        blue: 0xF2 / 255
    )
}