// Course.swift
//
// Mirrors plan.md §11. `id` is currently re-issued per scan; stable IDs
// tied to the sidecar come in Fase 5 (Sidecar + progreso).
//
// `Codable` is included from Fase 1 even though the sidecar itself ships
// in Fase 5 — the in-memory snapshot we already need (e.g. for sharing or
// future deep links) should round-trip via JSON without a refactor.

import Foundation

public struct Course: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var folderName: String
    public var title: String
    public var coverFileName: String?
    public var tags: [String]
    public var modules: [Module]

    public init(
        id: UUID = UUID(),
        folderName: String,
        title: String,
        coverFileName: String? = nil,
        tags: [String] = [],
        modules: [Module] = []
    ) {
        self.id = id
        self.folderName = folderName
        self.title = title
        self.coverFileName = coverFileName
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
