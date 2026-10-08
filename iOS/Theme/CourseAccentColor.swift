// CourseAccentColor.swift
//
// Theme-aware variant of the per-course accent color. Plan §14.1.1
// specifies two variants of the same dominant color:
//
//   * `courseAccentLight` — base color *darkened* ~20%, used as the
//     CTA fill in light mode.
//   * `courseAccentDark`  — base color *lightened* ~20%, used as the
//     CTA fill in dark mode.
//
// We implement that with a `UIColor(dynamicProvider:)` so a single
// `Color` value self-adjusts at paint time. This keeps the view code
// simple — it just uses the returned `Color` and SwiftUI's `Color`
// machinery asks the provider for the right value per `traitCollection`.
//
// Lives in iOS/ rather than Shared/ because it imports UIKit (the
// brightness adjustment needs `UIColor.getHue(...)`) and is purely a
// presentational helper; the macOS app reuses its own pipeline.

import SwiftUI
import UIKit

extension Color {
    /// Returns a new `Color` that automatically darkens in light mode
    /// and lightens in dark mode, relative to the input `base`. The
    /// hue and saturation are preserved; only the HSB brightness is
    /// scaled (~20%).
    ///
    /// Falls back to the input color if the conversion to HSB fails
    /// (e.g. for catalog colors the system can't represent in HSB).
    static func themeAdjusted(from base: Color) -> Color {
        let uiBase = UIColor(base)
        return Color(uiColor: UIColor { trait in
            adjust(uiBase, forDark: trait.userInterfaceStyle == .dark)
        })
    }

    private static func adjust(_ uiColor: UIColor, forDark: Bool) -> UIColor {
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a) else {
            return uiColor
        }
        let scaled: CGFloat = forDark ? min(b * 1.2, 1.0) : b * 0.8
        return UIColor(hue: h, saturation: s, brightness: scaled, alpha: a)
    }
}
