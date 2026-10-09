// MacCourseIndexer.swift
//
// Mac-side analog of `iOS/Library/CourseIndexer.swift`. Walks the
// user-configurable library root (default `~/Movies/CursosIpad/`) and
// returns a `[Course]` snapshot of what's there right now.
//
// Differences from the iOS indexer:
//
//   * **Root is configurable.** The library store owns the path and
//     passes it in via `Configuration.libraryURL`. iOS hardcodes
//     `Documents/Cursos/` because the OS puts the app there; the Mac
//     user picks wherever they keep their downloads.
//
//   * **No `AVAsset` pass.** The Mac editor doesn't display video
//     durations anywhere (Fase 10 may want them for the editor UI),
//     and walking every video on every refresh is wasted work. We
//     leave `durationSeconds` as `nil`; Fase 10's editor will compute
//     durations only for the lesson it's previewing.
//
//   * **No sidecar seeding.** The Mac app writes sidecars explicitly
//     when the user edits a course (Fase 9's "edit title / cover /
//     description" paths), not as a scan side effect. The iOS indexer
//     seeds because every fresh folder needs an ID and the progress
//     schema defaults; on Mac the folder only has a sidecar if the
//     user (or a future transfer from the iPad) already created one.
//
//   * **Synchronous on purpose.** The Mac scan happens during a
//     pull-to-refresh or a manual "Re-escanear" button; the user
//     expects a quick, predictable snapshot. AVAsset's async loading
//     was the main reason iOS needed an actor; without it a plain
//     `actor` would be overkill. We still use one for consistency with
//     the iOS API shape so callers can `await` either indifferently.

import Foundation
import Shared

public actor MacCourseIndexer {
    public struct Configuration: Sendable {
        public var libraryURL: URL
        public init(libraryURL: URL) {
            self.libraryURL = libraryURL
        }
    }

    private var configuration: Configuration
    private let fileManager: FileManager

    public init(
        configuration: Configuration,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    /// Convenience: update the library root (the user changed it in
    /// Settings) without re-creating the indexer.
    public func updateLibraryURL(_ url: URL) {
        configuration.libraryURL = url
    }

    /// Index the configured library root. Returns an empty array if
    /// the directory doesn't exist yet (the Mac user might have deleted
    /// `~/Movies/CursosIpad/` or pointed the app at a fresh folder).
    /// Sorted by `folderName` using `localizedStandardCompare` so the
    /// sidebar order matches Finder.
    public func index() async -> [Course] {
        let root = configuration.libraryURL
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir),
              isDir.boolValue else {
            return []
        }
        return indexDirectory(at: root)
    }

    // MARK: - Internals

    private func indexDirectory(at root: URL) -> [Course] {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("[MacCourseIndexer] Failed to list library root \(root.path): \(error)")
            return []
        }

        var courses: [Course] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            courses.append(buildCourse(at: entry, libraryRoot: root))
        }

        return courses.sorted { lhs, rhs in
            lhs.folderName.localizedStandardCompare(rhs.folderName) == .orderedAscending
        }
    }

    /// Build a single `Course` from a folder on disk. Mirrors the iOS
    /// indexer's structure (modules = first-level subdirectories,
    /// loose files in a virtual `General` module) so the two apps
    /// describe the same folder layout identically.
    private func buildCourse(at courseURL: URL, libraryRoot: URL) -> Course {
        let folderName = courseURL.lastPathComponent
        let title = folderName
        let coverFileName = detectCover(at: courseURL)

        var modules: [Module] = []
        var generalItems: [CourseItem] = []

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: courseURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("[MacCourseIndexer] Failed to list course dir \(courseURL.path): \(error)")
            return Course(
                folderName: folderName,
                title: title,
                coverFileName: coverFileName,
                tags: [],
                modules: []
            )
        }

        for entry in contents.sorted(by: {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }) {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let module = buildModule(at: entry, courseRoot: courseURL)
                modules.append(module)
            } else if let type = itemType(for: entry) {
                let item = buildItem(at: entry, type: type)
                generalItems.append(item)
            }
        }

        if !generalItems.isEmpty {
            modules.append(Module(
                folderName: "",
                title: "General",
                items: generalItems
            ))
        }

        let fresh = Course(
            folderName: folderName,
            title: title,
            coverFileName: coverFileName,
            tags: [],
            modules: modules
        )

        // Mirror the iOS indexer: overlay persisted metadata from the
        // sidecar if one exists. Today the iOS `apply()` consumes only
        // `courseId` + per-item progress (Fase 5), so a Mac edit to
        // title/cover/description stored in the sidecar won't surface
        // on the iPad until Fase 10 widens `apply()` per the plan.
        // We still apply it on the Mac so the in-memory `Course` is
        // consistent with what's on disk.
        guard let sidecar = SidecarStore.read(courseURL: courseURL, fileManager: fileManager) else {
            return fresh
        }
        return SidecarStore.apply(sidecar, to: fresh)
    }

    private func buildModule(at moduleURL: URL, courseRoot: URL) -> Module {
        let folderName = moduleURL.lastPathComponent
        let items = collectItems(in: moduleURL, courseRoot: courseRoot, currentlyRelativePath: folderName)
        return Module(
            folderName: folderName,
            title: folderName,
            items: items
        )
    }

    private func collectItems(
        in directory: URL,
        courseRoot: URL,
        currentlyRelativePath: String
    ) -> [CourseItem] {
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("[MacCourseIndexer] Failed to list module dir \(directory.path): \(error)")
            return []
        }

        var items: [CourseItem] = []
        for entry in contents.sorted(by: {
            $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending
        }) {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let nextRelative = "\(currentlyRelativePath)/\(entry.lastPathComponent)"
                items.append(contentsOf: collectItems(
                    in: entry,
                    courseRoot: courseRoot,
                    currentlyRelativePath: nextRelative
                ))
            } else if let type = itemType(for: entry) {
                let absoluteRelativePath = "\(currentlyRelativePath)/\(entry.lastPathComponent)"
                let item = buildItem(at: entry, type: type, relativePath: absoluteRelativePath)
                items.append(item)
            }
        }
        return items
    }

    /// Cover detection per plan §9: prefer `cover.jpg`, then `cover.png`,
    /// then the alphabetically first image in root. Returns the basename
    /// of the chosen cover, or `nil` if none.
    private func detectCover(at courseURL: URL) -> String? {
        let candidates: [URL]
        do {
            candidates = try fileManager.contentsOfDirectory(
                at: courseURL,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            return nil
        }

        let images = candidates.filter { url in
            ItemType.imageExtensions.contains(url.pathExtension.lowercased())
        }

        if let jpg = images.first(where: { $0.lastPathComponent.lowercased() == "cover.jpg" }) {
            return jpg.lastPathComponent
        }
        if let png = images.first(where: { $0.lastPathComponent.lowercased() == "cover.png" }) {
            return png.lastPathComponent
        }
        return images
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .first?
            .lastPathComponent
    }

    private func itemType(for url: URL) -> ItemType? {
        ItemType.from(extension: url.pathExtension)
    }

    private func buildItem(
        at url: URL,
        type: ItemType,
        relativePath: String? = nil
    ) -> CourseItem {
        let resolvedRelative = relativePath ?? url.lastPathComponent
        let title = (url.lastPathComponent as NSString).deletingPathExtension
        let size = (try? fileManager.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return CourseItem(
            relativePath: resolvedRelative,
            type: type,
            title: title,
            sizeBytes: size,
            durationSeconds: nil
        )
    }
}