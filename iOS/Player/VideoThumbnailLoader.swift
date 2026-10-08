// VideoThumbnailLoader.swift
//
// Per-row `@MainActor ObservableObject` used by `CurriculumLessonRow`.
// Wraps `ThumbnailGenerator.thumbnail(...)` with two responsibilities
// the row shouldn't have:
//
//   1. **Cancellation**. The row fires `start()` from `.task` and
//      `cancel()` from `.onDisappear`. The cancellation propagates
//      into the in-flight Task so a scroll that scrolls a row off
//      doesn't keep extracting frames for it.
//   2. **`@MainActor` publishing** of the resolved `UIImage`. Same
//      pattern as `CoverImageLoader` (`iOS/Library/CoverImageLoader.swift`)
//      — the loader takes the hit of swapping actors, the row just
//      observes `@Published var image`.
//
// Lives in `iOS/Player/` next to `ThumbnailGenerator` so the row's
// `import` surface is small (`CurriculumLessonRow` only needs this
// type; the `ThumbnailGenerator` enum stays internal).

import Foundation
import Shared
import SwiftUI
import UIKit

@MainActor
final class VideoThumbnailLoader: ObservableObject {

    /// Resolved thumbnail, or `nil` until `start()` completes. The
    /// row renders its placeholder (gradient + `play.fill`) while
    /// this is `nil`.
    @Published private(set) var image: UIImage?

    /// One lesson. `relativePath` is the unique key; the helper
    /// treats two video items with the same path as the same row
    /// (which can't happen — `relativePath` is unique within a course
    /// — but is a useful invariant to keep).
    private let item: CourseItem

    /// Absolute path to the course directory. The helper resolves
    /// `<video>.jpg` / `.thumbs/<safe>.jpg` relative to this.
    private let courseDirectory: URL

    /// Optional — the indexer may not have been able to read the
    /// video duration (corrupt file, network mount). When nil, the
    /// helper skips auto-generation and returns nil.
    private let durationSeconds: Double?

    /// In-flight task. `@StateObject` keeps a single instance per row
    /// identity, and `Task<Void, Never>` is cancelable.
    private var loadTask: Task<Void, Never>?

    init(
        item: CourseItem,
        courseDirectory: URL,
        durationSeconds: Double?
    ) {
        self.item = item
        self.courseDirectory = courseDirectory
        self.durationSeconds = durationSeconds
    }

    /// Spawn the load task. Safe to call multiple times — a second
    /// call replaces the prior task (canceling it first). The row
    /// wires this to `.task { loader.start() }`.
    func start() {
        loadTask?.cancel()
        let item = self.item
        let courseDirectory = self.courseDirectory
        let duration = self.durationSeconds
        loadTask = Task { [weak self] in
            let resolved = await ThumbnailGenerator.thumbnail(
                for: item,
                courseDirectoryURL: courseDirectory,
                durationSeconds: duration
            )
            // Hop to main before assigning so we stay `@MainActor`
            // safe under Swift 6 strict concurrency.
            await MainActor.run { [weak self] in
                guard let self else { return }
                if Task.isCancelled {
                    return
                }
                self.image = resolved
            }
        }
    }

    /// Cancel any in-flight resolution. Does NOT clear `image` — once
    /// a thumbnail has been resolved, we keep it (cheap UIImage, hot
    /// in the view binding).
    func cancel() {
        loadTask?.cancel()
        loadTask = nil
    }
}
