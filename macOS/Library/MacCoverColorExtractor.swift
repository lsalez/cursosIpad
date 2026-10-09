// MacCoverColorExtractor.swift
//
// Mac-side mirror of `iOS/Library/CoverColorExtractor.swift`. Pulls a
// dominant color out of a course cover for accent use. Same algorithm
// (downscale to 1×1, sample the resulting pixel) and same "useful"
// filter (saturation ≥ 0.15, brightness ∈ [0.2, 0.95]). Returns `nil`
// for grayscale/black/white covers so callers can fall back to
// `Color.appAccentFallback`.

import AppKit
import CoreGraphics
import SwiftUI

enum MacCoverColorExtractor {
    /// Extract the dominant color from the image at `url`, or `nil` if
    /// the result is too gray / dark / bright to be useful as an
    /// accent. Synchronous; the input image is downscaled to 1×1
    /// before sampling.
    static func dominantColor(of url: URL?) -> Color? {
        guard let url,
              let original = NSImage(contentsOf: url) else {
            return nil
        }
        guard original.size.width > 0, original.size.height > 0 else {
            return nil
        }

        // Render the image into a 1×1 bitmap. The single resulting
        // pixel is the area average — same trick the iOS version
        // uses with `UIGraphicsImageRenderer`.
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: 1,
            pixelsHigh: 1,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 4,
            bitsPerPixel: 32
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        original.draw(
            in: NSRect(origin: .zero, size: NSSize(width: 1, height: 1)),
            from: NSRect(origin: .zero, size: original.size),
            operation: .copy,
            fraction: 1.0
        )

        // Read the pixel via the bitmap rep's CGImage + data provider.
        // `NSBitmapImageRep.bitmapData` is typed (`UnsafeMutablePointer<UInt8>`)
        // in the AppKit overlay, but the cleanest path on macOS is
        // to go through `cgImage.dataProvider` and CoreFoundation's
        // `CFDataGetBytePtr` — same approach the iOS version uses
        // with `cgImage.dataProvider` directly.
        guard let cgImage = rep.cgImage,
              let dataProvider = cgImage.dataProvider,
              let cfData = dataProvider.data else {
            return nil
        }
        let length = CFDataGetLength(cfData)
        guard length >= 4 else { return nil }
        guard let bytes = CFDataGetBytePtr(cfData) else { return nil }
        let r = CGFloat(bytes[0]) / 255.0
        let g = CGFloat(bytes[1]) / 255.0
        let blue = CGFloat(bytes[2]) / 255.0
        let nsColor = NSColor(red: r, green: g, blue: blue, alpha: 1)

        guard let rgbColor = nsColor.usingColorSpace(.sRGB) else { return nil }
        var h: CGFloat = 0
        var s: CGFloat = 0
        var b: CGFloat = 0
        var a: CGFloat = 0
        // `NSColor.getHue` returns Void on macOS (no `Bool` overlay
        // like UIColor has). On failure the values stay at 0,0,0,0
        // and the saturation/brightness filter below rejects the
        // pixel — that's how we still skip non-RGB colors.
        rgbColor.getHue(&h, saturation: &s, brightness: &b, alpha: &a)

        // Same "is this useful as a CTA accent" filter as the iOS
        // version — keep these numbers in sync if either side changes.
        if s < 0.15 || b < 0.2 || b > 0.95 {
            return nil
        }

        return Color(nsColor: rgbColor)
    }
}