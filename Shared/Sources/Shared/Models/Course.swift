// Course.swift
//
// Mirrors plan.md §11.
//
// `id` was `let` during Fases 1–4 (re-issued per scan). In Fase 5 the
// sidecar takes over as the source of truth for `id`, so the indexer
// constructs a fresh `Course` (with whatever UUID happened to be
// minted) and `SidecarStore.apply` overwrites `id` from the persisted
// value. The field is now `var` to allow that single mutation site —
// nothing else in the app ever reassigns it.
//
// `Codable` is included from Fase 1 even though the sidecar itself ships
// in Fase 5 — the in-memory snapshot we already need (e.g. for sharing or
// future deep links) should round-trip via JSON without a refactor.

import Foundation

public struct Course: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: UUID
    public var folderName: String
    public var title: String
    public var coverFileName: String?
    public var description: String?
    public var tags: [String]
    public var modules: [Module]

    public init(
        id: UUID = UUID(),
        folderName: String,
        title: String,
        coverFileName: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        modules: [Module] = []
    ) {
        self.id = id
        self.folderName = folderName
        self.title = title
        self.coverFileName = coverFileName
        self.description = description
        self.tags = tags
        self.modules = modules
    }

    /// Fraction in `0.0...1.0`. Empty courses return `0` rather than NaN.
    public var totalProgress: Double {
        let items = allItems
        guard !items.isEmpty else { return 0 }
        let completed = items.filter(\.progress.isCompleted).count
        return Double(completed) / Double(items.count)
    }

    /// Sum of `items.count` across all modules, including the virtual
    /// `General` module when present.
    public var totalItemCount: Int {
        modules.reduce(0) { $0 + $1.items.count }
    }

    /// Flat list of items in display order (module order, items within module).
    public var allItems: [CourseItem] {
        modules.flatMap(\.items)
    }
}
