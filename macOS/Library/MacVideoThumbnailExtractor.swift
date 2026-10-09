// MacVideoThumbnailExtractor.swift
//
// macOS-side analog of `iOS/Player/ThumbnailGenerator.swift`. Extracts
// a video frame to a JPEG on disk for two distinct features:
//
//   1. **"Fijar este frame como miniatura"** (plan §13.4) — the Mac
//      editor's preview pane scrubs to a frame, the user clicks
//      the button, and we write that frame to `<video>.jpg` next to
//      the `.mp4`. The iOS app will pick it up as a user-supplied
//      thumbnail on its next index (priority 1 per plan §13.1).
//
//   2. **Auto-detect de portada mejorada** (Fase 10) — when the user
//      clicks "Auto-detectar" and the course has no image at root,
//      we fall back to extracting a frame from the first video at
//      25% of its duration and saving as `cover.jpg`.
//
// Mirrors the iOS implementation's frame size and JPEG quality so
// the resulting files look the same on both platforms. Uses
// `CGImage` (not `NSImage`) because the on-disk pipeline is JPEG
// encode → write, with no UI intermediate — keeps the extractor
// independent of `AppKit`'s image machinery.

import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public enum MacVideoThumbnailExtractor {

    /// Output dimensions per plan §13. Same as
    /// `iOS/Player/ThumbnailGenerator.frameSize`.
    public static let frameSize = CGSize(width: 320, height: 180)

    /// JPEG quality per plan §13. Same as the iOS extractor.
    public static let jpegQuality: CGFloat = 0.7

    /// Extract a frame at `time` from `videoURL` and write it as
    /// JPEG to `destinationURL`. Replaces any existing file at the
    /// destination. Returns `true` on success.
    ///
    /// - Parameters:
    ///   - videoURL: absolute URL of the source video.
    ///   - time: `CMTime` to extract. For "Fijar este frame" this
    ///     comes from the live `AVPlayer.currentTime()`. For the
    ///     auto-detect fallback, callers pass `duration * 0.25`.
    ///   - destinationURL: where to write the resulting JPEG. The
    ///     parent directory is created if missing.
    ///   - fileManager: injectable for tests.
    public static func extractFrame(
        fromVideo videoURL: URL,
        at time: CMTime,
        writeTo destinationURL: URL,
        fileManager: FileManager = .default
    ) async -> Bool {
        let cgImage: CGImage? = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = frameSize
            do {
                // Sync API. The async
                // `generateCGImageAsynchronously(for:completionHandler:)`
                // variant is the macOS 15+ recommendation, but its
                // callback shape doesn't compose with the
                // `Task.detached` + optional-bridge this extractor
                // uses, and the sync version is still fully supported
                // on macOS 14 (this project's deployment target per
                // `project.yml`). The same call shape is used by
                // `iOS/Player/ThumbnailGenerator.swift:200` for
                // consistency. Migration is a future change.
                return try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                print("[MacVideoThumbnailExtractor] Extract failed for \(videoURL.lastPathComponent) @ \(time.seconds)s: \(error)")
                return nil
            }
        }.value
        guard let cgImage else { return false }
        return writeJPEG(cgImage, to: destinationURL, fileManager: fileManager)
    }

    // MARK: - JPEG writer

    private static func writeJPEG(
        _ image: CGImage,
        to url: URL,
        fileManager: FileManager
    ) -> Bool {
        let dir = url.deletingLastPathComponent()
        do {
            if !fileManager.fileExists(atPath: dir.path) {
                try fileManager.createDirectory(
                    at: dir,
                    withIntermediateDirectories: true
                )
            }
        } catch {
            print("[MacVideoThumbnailExtractor] Failed to create directory for \(url.path): \(error)")
            return false
        }

        let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        )
        guard let destination else {
            print("[MacVideoThumbnailExtractor] CGImageDestinationCreateWithURL failed for \(url.path)")
            return false
        }
        let options: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: jpegQuality
        ]
        CGImageDestinationAddImage(destination, image, options as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            print("[MacVideoThumbnailExtractor] CGImageDestinationFinalize failed for \(url.path)")
            return false
        }
        return true
    }
}
