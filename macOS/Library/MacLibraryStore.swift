// MacLibraryStore.swift
//
// State for the macOS app. Mirrors the shape of
// `iOS/Library/LibraryStore.swift` but trimmed to what the Mac editor
// actually needs in Fase 9:
//
//   * Owns a `MacCourseIndexer` and exposes its `[Course]` snapshot
//     to SwiftUI views as `@Published`.
//   * Owns the library root path (defaults to `~/Movies/CursosIpad/`)
//     and persists changes to `UserDefaults` so the user's choice
//     survives app restarts. The setter mutates both the indexer and
//     the published path so views see the new path immediately and a
//     subsequent `refresh()` re-scans the new location.
//
// The Mac app doesn't need the iOS search/cover-accent/per-item
// progress plumbing — those belong to the iOS target. The Mac editor
// only needs the indexed snapshot + a way to refresh + a way to
// persist edits to the sidecar.

import Combine
import Foundation
import Shared
import SwiftUI

@MainActor
final class MacLibraryStore: ObservableObject {
    @Published private(set) var courses: [Course] = []
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    /// Library root, persisted in `UserDefaults`. Defaults to
    /// `~/Movies/CursosIpad/`. Changing it kicks off a refresh.
    @Published var libraryURL: URL {
        didSet {
            guard libraryURL != oldValue else { return }
            MacSettings.saveLibraryURL(libraryURL)
            Task { await applyNewLibraryURL(libraryURL) }
        }
    }

    private let indexer: MacCourseIndexer
    private let fileManager: FileManager

    init(
        libraryURL: URL = MacSettings.defaultLibraryURL(),
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.libraryURL = libraryURL
        self.indexer = MacCourseIndexer(
            configuration: MacCourseIndexer.Configuration(libraryURL: libraryURL),
            fileManager: fileManager
        )
    }

    // MARK: - Refresh

    /// Re-scan the library root and update `courses`. Cheap — the
    /// Mac indexer does a single recursive walk (no AVAsset pass).
    func refresh() async {
        isLoading = true
        defer { isLoading = false }
        do {
            let result = await indexer.index()
            courses = result
            lastError = nil
        }
    }

    // MARK: - Settings

    private func applyNewLibraryURL(_ url: URL) async {
        await indexer.updateLibraryURL(url)
        await refresh()
    }

    /// Used by the WelcomeScreen's "Open folder…" button: starts a
    /// picker at the user's current library root so they don't have
    /// to navigate from `~/` every time.
    func currentLibraryURLForPicker() -> URL {
        libraryURL
    }
}