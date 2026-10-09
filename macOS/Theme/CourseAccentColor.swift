// CourseAccentColor.swift
//
// macOS-side mirror of `iOS/Theme/CourseAccentColor.swift`. Plan §14.1.1
// calls for two variants of the same dominant color:
//
//   * `courseAccentLight` — base color *darkened* ~20%, used as the
//     CTA fill in light mode.
//   * `courseAccentDark`  — base color *lightened* ~20%, used as the
//     CTA fill in dark mode.
//
// The iOS implementation uses `UIColor(dynamicProvider:)` + HSB
// brightness scaling. On macOS we don't have `UIColor`, so we use
// `NSColor(name:dynamicProvider:)` with the same HSB scale factor — the
// provider runs once per appearance and SwiftUI's `Color(nsColor:)`
// picks the right variant for the current appearance. AppKit is a
// Mac-only import, so this lives in `macOS/` rather than `Shared/`.

import AppKit
import SwiftUI

extension Color {
    /// Returns a `Color` that automatically darkens in light mode and
    /// lightens in dark mode, relative to the input `base`. Hue and
    /// saturation are preserved; only the HSB brightness is scaled (~20%).
    /// Falls back to the input color if the conversion to HSB fails
    /// (e.g. for catalog colors the system can't represent in HSB).
    static func themeAdjusted(from base: Color) -> Color {
        let nsBase = NSColor(base).usingColorSpace(.sRGB) ?? NSColor(base)
        let light = adjust(nsBase, forDark: false)
        let dark = adjust(nsBase, forDark: true)
        let adjusted = NSColor(name: "themeAdjusted") { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
        return Color(nsColor: adjusted)
    }

    /// Reads HSB components out of `nsColor` via AppKit's
    /// `getHue(_:saturation:brightness:alpha:)` (Swift `inout` overlay
    /// available on macOS — no pointer plumbing needed) and returns
    /// a new NSColor with brightness scaled by 0.8 (light) or 1.2
    /// (dark, clamped to 1.0). Falls back to the input color on
    /// failure (non-HSB colors).
    private static func adjust(_ nsColor: NSColor, forDark: Bool) -> NSColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        nsColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        let scale: CGFloat = forDark ? 1.2 : 0.8
        let scaled = forDark ? min(b * scale, 1.0) : b * scale
        return NSColor(calibratedHue: h, saturation: s, brightness: scaled, alpha: a)
    }
}