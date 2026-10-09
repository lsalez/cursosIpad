// Sidecar.swift
//
// On-disk persistence for a single course. Plan §12 specifies the JSON
// shape that lives at the root of every course folder as
// `.cursosIpad.json`. This file defines the two Codable types that
// round-trip that JSON:
//
//   * `Sidecar` — one per course; carries the course's stable `courseId`,
//     mutable metadata (title, description, tags, coverFileName) and
//     the per-item progress map.
//   * `SidecarItem` — one per `CourseItem`, keyed by the item's
//     `relativePath`.
//
// Date encoding strategy (ISO8601) is centralized in `SidecarStore` —
// read the comment there before changing the schema.
//
// **Contract boundary (Fase 10):**
//   * On read, `courseId`, `description`, `tags`, and per-item
//     `progress` are pulled into the in-memory `Course` via
//     `SidecarStore.apply`. The other fields (`title`,
//     `coverFileName`) stay filesystem-derived so renaming a folder
//     in Finder flows through to the UI without a Mac editor
//     round-trip. (Fase 5 only consumed `courseId` + progress; Fase 10
//     widens the consumed subset to include `description` and `tags`
//     once the Mac editor exists.)
//   * On write, all fields are persisted.
//   * `updatedAt` is set by `SidecarStore.write` itself; callers never
//     set it. This keeps every fresh write timestamped identically.
//
// Items are keyed by `relativePath`, faithful to plan §12. Renames
// inside a course therefore orphan progress silently — that's a known
// limitation, documented in plan §20 as Fase 5 follow-up work for
// when the Mac editor lands.

import Foundation

public struct Sidecar: Codable, Equatable, Sendable {
    /// Schema version. Bump when the on-disk shape changes in a way
    /// that can't be inferred from optional fields (e.g. removing or
    /// renaming a field). `SidecarStore.read` returns `nil` on any
    /// decode failure, so the indexer re-seeds a fresh v1 — losing
    /// user data is preferable to a crash, but see the corruption
    /// recovery comment in `SidecarStore` for the `.bak` path.
    public var version: Int

    /// Stable identity for the course. Mints at first index, then
    /// re-used across all subsequent reads of this sidecar. This is
    /// the value that lets `Course.id` survive a `LibraryStore.refresh()`.
    public var courseId: UUID

    public var title: String
    public var coverFileName: String?
    public var description: String?
    public var tags: [String]

    /// Keyed by `CourseItem.relativePath`. See file header for why
    /// we don't use stable item UUIDs yet (Fase 5 follow-up).
    public var items: [String: SidecarItem]

    /// Last write timestamp. **Do not set at the call site** — the
    /// writer stamps it on every successful persistence. Callers that
    /// construct a `Sidecar` (e.g. `SidecarStore.empty(course:)`,
    /// `SidecarStore.snapshot(course:)`) leave this `nil`.
    public var updatedAt: Date?

    public init(
        version: Int = 1,
        courseId: UUID,
        title: String,
        coverFileName: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        items: [String: SidecarItem] = [:],
        updatedAt: Date? = nil
    ) {
        self.version = version
        self.courseId = courseId
        self.title = title
        self.coverFileName = coverFileName
        self.description = description
        self.tags = tags
        self.items = items
        self.updatedAt = updatedAt
    }
}

public struct SidecarItem: Codable, Equatable, Sendable {
    /// Redundant with the file extension but useful as a cross-check
    /// if files are renamed (Fase 10 may use this to surface "the file
    /// you watched isn't the file in this slot anymore"). For now,
    /// readers can ignore it; we always write it.
    public var type: ItemType

    public var lastViewedAt: Date?
    /// Position in seconds. Used for video (`AVPlayer.currentTime`)
    /// and HTML (mapped from scroll px). `nil` for PDFs.
    public var positionSeconds: Double?
    /// Last viewed page, 1-indexed. Only meaningful for PDFs.
    public var lastPage: Int?
    public var isCompleted: Bool
    public var completionMarkedAt: Date?

    public init(
        type: ItemType,
        lastViewedAt: Date? = nil,
        positionSeconds: Double? = nil,
        lastPage: Int? = nil,
        isCompleted: Bool = false,
        completionMarkedAt: Date? = nil
    ) {
        self.type = type
        self.lastViewedAt = lastViewedAt
        self.positionSeconds = positionSeconds
        self.lastPage = lastPage
        self.isCompleted = isCompleted
        self.completionMarkedAt = completionMarkedAt
    }

    /// Lift the progress this item represents onto a default-empty
    /// `ItemProgress` (used when wiring sidecar data onto freshly-
    /// discovered `CourseItem`s).
    public var asItemProgress: ItemProgress {
        ItemProgress(
            lastViewedAt: lastViewedAt,
            positionSeconds: positionSeconds,
            lastPage: lastPage,
            isCompleted: isCompleted,
            completionMarkedAt: completionMarkedAt
        )
    }
}

// Bridge from the freshly-built `CourseItem.progress` back into the
// stored `SidecarItem` representation. Lives here (in the Shared
// target) so the conversion logic sits next to both types and any
// future schema tweaks only touch one file.
extension SidecarItem {
    /// Construct a `SidecarItem` snapshot from an in-memory
    /// `CourseItem`. Used by `SidecarStore.snapshot(course:)` to
    /// build a writeable sidecar from the live course state.
    public init(courseItem: CourseItem) {
        self.init(
            type: courseItem.type,
            lastViewedAt: courseItem.progress.lastViewedAt,
            positionSeconds: courseItem.progress.positionSeconds,
            lastPage: courseItem.progress.lastPage,
            isCompleted: courseItem.progress.isCompleted,
            completionMarkedAt: courseItem.progress.completionMarkedAt
        )
    }
}
