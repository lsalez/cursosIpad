// Module.swift
//
// Mirrors plan.md §11. The `folderName` is the on-disk folder name
// verbatim; `title` defaults to it. Stripping numeric prefixes like
// `01 ` is deferred to Fase 10 (Mac editor) so the iOS library renders
// whatever sits on disk without us inventing formatting rules.
//
// `folderName == ""` is the convention for the virtual `General` module
// that bundles loose files from a course's root (see plan §9 ⚠️ #6,
// resolved during Fase 1 planning: include the General module).

import Foundation

public struct Module: Identifiable, Codable, Equatable, Hashable, Sendable {
    public let id: UUID
    public var folderName: String
    public var title: String
    public var items: [CourseItem]

    public init(
        id: UUID = UUID(),
        folderName: String,
        title: String,
        items: [CourseItem] = []
    ) {
        self.id = id
        self.folderName = folderName
        self.title = title
        self.items = items
    }

    /// True iff the module has at least one item and every item is completed.
    public var isFullyCompleted: Bool {
        !items.isEmpty && items.allSatisfy(\.progress.isCompleted)
    }
}
