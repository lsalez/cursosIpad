// ItemProgress.swift
//
// Mirrors plan.md §11. Default-initialized as empty so `CourseIndexer`
// can build a fresh `ItemProgress()` for every item on a first scan
// (Fase 1, before the sidecar exists — Fase 5 introduces the sidecar
// and will merge persisted progress onto these defaults).
//
// The fields are intentionally permissive about being `nil`: only the
// values that are meaningful for the item's type get set.
// - `positionSeconds` is for video and HTML (scroll position, expressed
//   in "virtual seconds" — see plan §17).
// - `lastPage` is for PDF only.

import Foundation

public struct ItemProgress: Codable, Equatable, Hashable, Sendable {
    public var lastViewedAt: Date?
    public var positionSeconds: Double?
    public var lastPage: Int?
    public var isCompleted: Bool
    public var completionMarkedAt: Date?

    public init(
        lastViewedAt: Date? = nil,
        positionSeconds: Double? = nil,
        lastPage: Int? = nil,
        isCompleted: Bool = false,
        completionMarkedAt: Date? = nil
    ) {
        self.lastViewedAt = lastViewedAt
        self.positionSeconds = positionSeconds
        self.lastPage = lastPage
        self.isCompleted = isCompleted
        self.completionMarkedAt = completionMarkedAt
    }
}
