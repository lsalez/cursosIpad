// CoverColorExtractor.swift
//
// Pulls a "useful" dominant color out of a course's cover image. Useful
// here means: saturated enough and mid-bright enough to read as a CTA
// accent against the SPID chrome. Returns `nil` when the cover is
// basically grayscale / black / white — in that case the caller falls
// back to `Color.appAccentFallback` (the brand purple).
//
// Implementation: downscale the image to a 1×1 bitmap with
// `UIGraphicsImageRenderer`. That single pixel is the area average of
// the whole image, which is good enough for "what color does this
// course feel like" and is one allocation regardless of cover size.
//
// Lives in iOS/ rather than Shared/ because it imports UIKit and uses
// the courses directory resolution; the macOS editor in Fase 10 has
// its own pipeline (it can also let the user pick a frame by hand).

import SwiftUI
import UIKit

enum CoverColorExtractor {
    /// Extract the dominant color from the image at `url`, or `nil` if
    /// the result is too gray / dark / bright to be useful as a CTA
    /// accent. Always synchronous; the input image is downscaled to 1×1
    /// before sampling.
    static func dominantColor(of url: URL) -> Color? {
        guard let original = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        guard original.size.width > 0, original.size.height > 0 else {
            return nil
        }

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1, height: 1))
        let rendered = renderer.image { _ in
            original.draw(in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }

        guard
            let cgImage = rendered.cgImage,
            let dataProvider = cgImage.dataProvider,
            let data = dataProvider.data,
            let ptr = CFDataGetBytePtr(data)
        else {
            return nil
        }

        let r = CGFloat(ptr[0]) / 255.0
        let g = CGFloat(ptr[1]) / 255.0
        let b = CGFloat(ptr[2]) / 255.0
        let uiColor = UIColor(red: r, green: g, blue: b, alpha: 1)

        var h: CGFloat = 0
        var s: CGFloat = 0
        var brightness: CGFloat = 0
        var a: CGFloat = 0
        guard uiColor.getHue(&h, saturation: &s, brightness: &brightness, alpha: &a) else {
            return nil
        }

        // Reject near-grayscale, very dark, and very light averages —
        // none of those would be a legible button color on either
        // background variant.
        if s < 0.15 || brightness < 0.2 || brightness > 0.95 {
            return nil
        }

        return Color(uiColor)
    }
}
