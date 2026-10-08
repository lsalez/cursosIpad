// CourseItem.swift
//
// Mirrors plan.md §11. `relativePath` is always relative to the course
// root, e.g. `"01 Introduccion/bienvenido.mp4"`. We don't keep a separate
// `modulePath` / `filename` pair — the relative path is the source of
// truth and `filename` is derived from its last component.
//
// `durationSeconds` is filled in by `CourseIndexer` for videos via
// `AVAsset.load(.duration)` (see plan §13). PDFs and HTMLs always have it
// set to nil.

import Foundation

public struct CourseItem: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var relativePath: String
    public var type: ItemType
    public var title: String
    public var sizeBytes: Int64
    public var durationSeconds: Double?
    public var progress: ItemProgress

    public init(
        id: UUID = UUID(),
        relativePath: String,
        type: ItemType,
        title: String,
        sizeBytes: Int64,
        durationSeconds: Double? = nil,
        progress: ItemProgress = ItemProgress()
    ) {
        self.id = id
        self.relativePath = relativePath
        self.type = type
        self.title = title
        self.sizeBytes = sizeBytes
        self.durationSeconds = durationSeconds
        self.progress = progress
    }

    /// Last path component of `relativePath` (e.g. `"bienvenido.mp4"`).
    public var filename: String {
        (relativePath as NSString).lastPathComponent
    }
}
