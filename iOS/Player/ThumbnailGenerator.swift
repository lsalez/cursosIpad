// ThumbnailGenerator.swift
//
// Lazy, cached thumbnail generation for video lessons. Plan §13 spells
// out the priority order:
//
//   1. **User-supplied** — `<filename>.jpg` (or .jpeg/.png/.heic) next
//      to the `.mp4`. If present, wins over everything else.
//   2. **Auto-generated, cached** — first call extracts a frame at 25%
//      of `durationSeconds` via `AVAssetImageGenerator`, encodes as
//      JPEG q=0.7 at most 320×180, and writes it to
//      `<course>/.thumbs/<safe-name>.jpg`. Subsequent calls hit the
//      disk cache.
//   3. **Placeholder** (caller's responsibility — returns `nil`).
//
// `.thumbs/` is **not** transferred over WiFi in Fase 11 — it's a
// device-local cache the iPad regenerates itself.
//
// **Concurrency**: runs inside `Task.detached(priority: .utility)` to
// keep `copyCGImage` off the main thread, and goes through
// `ThumbnailQueue` to cap concurrent extractions at 4. A library with
// 50 video lessons won't fire 50 AVAsset opens on first scroll —
// they'll queue up. The `ItemType.imageExtensions` set is the single
// source of truth for which extensions we recognize as user-supplied
// thumbnails (`Shared/Sources/Shared/Models/ItemType.swift:46`); we
// don't redeclare the list here.

import AVFoundation
import Foundation
import Shared
import UIKit

enum ThumbnailGenerator {

    /// Limits per plan §13 — small enough to be cache-friendly, big
    /// enough to look like a thumbnail in `CurriculumLessonRow`.
    static let frameSize = CGSize(width: 320, height: 180)
    static let jpegQuality: CGFloat = 0.7

    /// Subfolder inside the course directory that holds auto-generated
    /// thumbnails. Leading dot keeps it hidden in Finder; the
    /// indexer's `.skipsHiddenFiles` walks ignore it.
    static let thumbsSubdirectory = ".thumbs"

    /// Resolves the best available thumbnail, writing to the cache if
    /// a new auto-generated one had to be produced. Returns `nil` if
    /// no thumbnail could be produced (placeholder is the caller's
    /// responsibility).
    ///
    /// - Parameters:
    ///   - item: the lesson — `relativePath` and `type == .video`
    ///     decide whether we even try.
    ///   - courseDirectoryURL: absolute path to the course folder.
    ///     The thumbnail paths are siblings of the video file.
    ///   - durationSeconds: optional; the indexer may not have been
    ///     able to read it (corrupt MP4, network mount stalled). If
    ///     nil and no user-supplied + no cached thumb exist, we
    ///     return nil rather than guessing a frame.
    ///   - fileManager: injectable for tests.
    static func thumbnail(
        for item: CourseItem,
        courseDirectoryURL: URL,
        durationSeconds: Double?,
        fileManager: FileManager = .default
    ) async -> UIImage? {
        // Step 1 — user-supplied thumbnail next to the video file.
        if let userSupplied = locateUserSuppliedThumbnail(
            for: item,
            courseDirectoryURL: courseDirectoryURL,
            fileManager: fileManager
        ) {
            return userSupplied
        }

        let cachedURL = cachedThumbnailURL(
            for: item,
            courseDirectoryURL: courseDirectoryURL
        )

        // Step 2a — cached auto-generated thumbnail hit.
        if fileManager.fileExists(atPath: cachedURL.path),
           let cached = UIImage(contentsOfFile: cachedURL.path) {
            return cached
        }

        // Step 2b — generate. Need a duration to pick the frame; if we
        // don't have one we can't extract a meaningful 25%-of-duration
        // frame, so return nil and let the caller show a placeholder.
        guard let durationSeconds, durationSeconds > 0 else {
            return nil
        }

        await ThumbnailQueue.shared.acquire()
        defer {
            // Release from a Task so we don't suspend on the actor
            // during teardown of the caller (which is fine but adds
            // latency to the row's appearance).
            Task { await ThumbnailQueue.shared.release() }
        }

        let videoURL = courseDirectoryURL.appendingPathComponent(
            item.relativePath,
            isDirectory: false
        )
        let frame = await Self.extractFrame(
            videoURL: videoURL,
            atSecond: durationSeconds * 0.25
        )
        guard let frame else { return nil }

        // Cache on disk so the next call short-circuits.
        try? writeJPEG(frame, to: cachedURL, fileManager: fileManager)

        return frame
    }

    // MARK: - User-supplied lookup

    /// Looks for `<video-name>.<ext>` next to the video file, for
    /// every ext in `ItemType.imageExtensions`. Returns the first
    /// match's `UIImage`, or nil.
    private static func locateUserSuppliedThumbnail(
        for item: CourseItem,
        courseDirectoryURL: URL,
        fileManager: FileManager
    ) -> UIImage? {
        let videoURL = courseDirectoryURL.appendingPathComponent(
            item.relativePath,
            isDirectory: false
        )
        // Strip the original extension; append each image ext in turn.
        // `deletingPathExtension` doesn't fail on already-stripped
        // names — it just returns the original URL — so this is safe
        // for items whose `relativePath` has no extension (which
        // shouldn't happen for videos but defensive).
        let stemURL = videoURL.deletingPathExtension()
        for ext in ItemType.imageExtensions {
            let candidate = stemURL.appendingPathExtension(ext)
            if fileManager.fileExists(atPath: candidate.path),
               let image = UIImage(contentsOfFile: candidate.path) {
                return image
            }
        }
        return nil
    }

    // MARK: - Cached URL

    /// `safeName` strips the directory separators so that a video at
    /// `01 Introduccion/bienvenido.mp4` becomes a single flat filename
    /// in `.thumbs/` (`01__Introduccion__bienvenido.mp4.jpg`). Without
    /// this, subdirectories inside `.thumbs/` would re-introduce the
    /// exact problem we're trying to avoid.
    private static func cachedThumbnailURL(
        for item: CourseItem,
        courseDirectoryURL: URL
    ) -> URL {
        let safe = safeName(for: item.relativePath)
        let thumbsDir = courseDirectoryURL.appendingPathComponent(
            thumbsSubdirectory,
            isDirectory: true
        )
        return thumbsDir.appendingPathComponent(safe)
    }

    static func safeName(for relativePath: String) -> String {
        // Replace path separators with `__` and append a deterministic
        // `.jpg` suffix (the cache is always a JPEG; user-supplied
        // thumbnails keep their original extension via
        // `locateUserSuppliedThumbnail`).
        let flat = relativePath.replacingOccurrences(of: "/", with: "__")
        // `URL(fileURLWithPath:)` parses dot-separated extensions;
        // we don't care — we always write `.jpg`. Strip whatever
        // extension is there to avoid `<base>.<ext>.jpg` doubling.
        let stem = (flat as NSString).deletingPathExtension
        return stem + ".jpg"
    }

    // MARK: - Frame extraction

    /// Decodes a single frame at `seconds` from `videoURL`. Runs
    /// inside `Task.detached` because `copyCGImage` is blocking and
    /// can take 100-500ms on cold iPad for 1080p sources. Returns
    /// `nil` for any decode failure — caller falls back to placeholder.
    private static func extractFrame(
        videoURL: URL,
        atSecond seconds: Double
    ) async -> UIImage? {
        let image: CGImage? = await Task.detached(priority: .utility) {
            let asset = AVURLAsset(url: videoURL)
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = frameSize
            let time = CMTime(seconds: seconds, preferredTimescale: 600)
            do {
                // Sync API: returns the CGImage directly. Pre-iOS 16
                // style but works on every iOS 17 SDK. The async
                // `image(at:)` variant is iOS 16+ but its return
                // shape (tuple) trips the closure-inference; the sync
                // version reads cleaner here.
                return try generator.copyCGImage(at: time, actualTime: nil)
            } catch {
                print("[ThumbnailGenerator] Extract failed for \(videoURL.lastPathComponent) @ \(seconds)s: \(error)")
                return nil
            }
        }.value
        guard let image else { return nil }
        return UIImage(cgImage: image)
    }

    // MARK: - JPEG writer

    private static func writeJPEG(
        _ image: UIImage,
        to url: URL,
        fileManager: FileManager
    ) throws {
        let dir = url.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: dir,
            withIntermediateDirectories: true
        )
        guard let data = image.jpegData(compressionQuality: jpegQuality) else {
            return
        }
        try data.write(to: url, options: [.atomic])
    }
}

// MARK: - ThumbnailQueue

/// Tiny semaphore-style actor that caps concurrent thumbnail
/// generations at 4. A library view scrolling into 50 video cells at
/// once fans out 50 awaits — without this they'd all reach for
/// `AVAssetImageGenerator.copyCGImage` simultaneously. The cost is
/// mostly the AVAsset open, not the frame extraction.
///
/// The pattern (mutex + FIFO waiters) is intentionally simpler than
/// `AsyncSemaphore`. The acquisition is `await` only if we're at the
/// cap; otherwise it's instantaneous — exactly what we want for the
/// common case.
actor ThumbnailQueue {
    static let shared = ThumbnailQueue()

    /// Max concurrent generators. 4 is arbitrary but matches iPad's
    /// typical core count — empirical; bumps to 8 haven't helped.
    private let maxConcurrent = 4

    private var inflight = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        if inflight < maxConcurrent {
            inflight += 1
            return
        }
        await withCheckedContinuation { cont in
            waiters.append(cont)
        }
    }

    func release() {
        precondition(inflight > 0, "release() called without a matching acquire()")
        inflight -= 1
        if let next = waiters.first {
            waiters.removeFirst()
            inflight += 1
            next.resume()
        }
    }
}
