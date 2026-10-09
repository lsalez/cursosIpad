// CourseIndexer.swift
//
// Walks the iOS app's `Documents/` directory and returns a `[Course]`
// snapshot of what's there right now. Each immediate subfolder of
// `Documents/` is treated as a course (if its name doesn't start with
// a dot). Plan §9 has the detection rules; this file is the concrete
// implementation.
//
// Decision history: earlier revisions kept courses under a
// `Documents/Cursos/` subfolder, but in practice that meant USB
// transfers from Finder needed to land in `cursosIpad/Cursos/<course>/`
// instead of `cursosIpad/<course>/`. The subfolder was dropped —
// the indexer now scans `Documents/` directly so that what the user
// drags into the app's File Sharing location is exactly what shows
// up in the library. See plan §9 and §19 for the decision.
//
// Lives in the iOS target (not in `Shared/`) because the indexer is
// application logic on top of the model layer, and the macOS app will
// get its own indexer in Fase 9 with slightly different rules.
//
// Performance shape:
// 1. Fast recursive filesystem walk. Single-threaded. Should be a few
//    hundred ms for a few hundred files.
// 2. After the walk, a sequential AVAsset pass for video durations.
//    Each `asset.load(.duration)` is on-demand but bounded; errors on
//    individual files don't abort the scan — they just leave
//    `durationSeconds` nil and get logged.
// Errors don't bubble up unless the root directory itself is unreadable.

import AVFoundation
import Foundation
import Shared

public actor CourseIndexer {
    public struct Configuration: Sendable {
        /// Subdirectory inside `Documents/` to scan. Default is `""`
        /// (empty), which means the indexer scans `Documents/` itself.
        /// Any non-empty value keeps the legacy nested layout
        /// (`Documents/<name>/<courses>`) — useful for tests or for a
        /// future "isolate course content from other app files" mode,
        /// but not used in production.
        public var documentsSubdirectory: String = ""
        public init() {}
    }

    private let configuration: Configuration
    private let fileManager: FileManager

    public init(
        configuration: Configuration = .init(),
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    /// Index the courses root (see `Configuration.documentsSubdirectory`).
    /// Returns an empty array if the directory doesn't exist yet (first
    /// launch, or `Documents/` was just created). Sorted by `folderName`
    /// using `localizedStandardCompare`.
    public func index() async throws -> [Course] {
        let coursesRoot = try resolveCoursesRoot()
        guard let coursesRoot else { return [] }
        return try await indexDirectory(at: coursesRoot)
    }

    // MARK: - Internals

    /// Resolves the on-disk location to scan. Returns `nil` if the
    /// Documents directory can't be located (extremely unusual on iOS).
    private func resolveCoursesRoot() throws -> URL? {
        guard let docs = fileManager.urls(
            for: .documentDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        let subdirectory = configuration.documentsSubdirectory
        let root: URL = subdirectory.isEmpty
            ? docs
            : docs.appendingPathComponent(subdirectory, isDirectory: true)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: root.path, isDirectory: &isDir),
              isDir.boolValue else {
            return nil
        }
        return root
    }

    private func indexDirectory(at coursesRoot: URL) async throws -> [Course] {
        let entries: [URL]
        do {
            entries = try fileManager.contentsOfDirectory(
                at: coursesRoot,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            print("[CourseIndexer] Failed to list courses root \(coursesRoot.path): \(error)")
            return []
        }

        var courses: [Course] = []
        for entry in entries {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            guard isDir else { continue }
            let course = buildCourse(at: entry, coursesRoot: coursesRoot)
            courses.append(course)
        }

        let withDurations = await prefetchVideoDurations(courses: courses, coursesRoot: coursesRoot)
        // Sort before persisting so the writer walks courses in a
        // stable order (avoids racing re-orders when the user pulls
        // to refresh twice in a row).
        let sorted = withDurations.sorted { lhs, rhs in
            lhs.folderName.localizedStandardCompare(rhs.folderName) == .orderedAscending
        }
        await seedMissingSidecars(courses: sorted, coursesRoot: coursesRoot)
        return sorted
    }

    /// Walk the freshly-built `[Course]` and write a fresh sidecar
    /// for any folder that doesn't have one yet. Lives here (not
    /// inside `buildCourse`) for two reasons, both from the Fase 5
    /// review: keeping `buildCourse` purely synchronous prevents the
    /// actor from blocking on disk I/O, and running the writes after
    /// the full build lets a reentrant `index()` see stable state.
    ///
    /// Errors are logged but never abort the scan; matching the
    /// indexer's "be lenient" convention. Already-present sidecars
    /// are *not* rewritten here — `LibraryStore.markCourseCompleted`
    /// (and later, the per-item visors) own ongoing writes.
    private func seedMissingSidecars(
        courses: [Course],
        coursesRoot: URL
    ) async {
        for course in courses {
            let courseURL = coursesRoot.appendingPathComponent(
                course.folderName,
                isDirectory: true
            )
            let sidecarURL = SidecarStore.sidecarURL(for: courseURL)
            // Cheap stat — no decode, no allocation worth worrying
            // about on the actor.
            guard !fileManager.fileExists(atPath: sidecarURL.path) else {
                continue
            }
            let seed = SidecarStore.empty(course: course)
            do {
                try await SidecarStore.write(
                    seed,
                    to: courseURL,
                    fileManager: fileManager
                )
            } catch {
                print("[CourseIndexer] Failed to seed sidecar for \(course.folderName): \(error)")
            }
        }
    }

    /// One-shot scan of a single course folder. Collects: cover filename,
    /// a `Module` for each first-level subdirectory, plus a virtual
    /// `General` `Module` for any recognized files sitting in the root.
    ///
    /// After the filesystem walk, merges in the persisted sidecar
    /// (Fase 5): if `.cursosIpad.json` exists, its `courseId` becomes
    /// the course's `id` (stable across scans) and its per-item
    /// `progress` overlays each freshly-discovered item. The fresh
    /// sidecar for newly-seen courses is written later, in
    /// `seedMissingSidecars`, after the whole `indexDirectory` walk
    /// completes — see that method for why.
    private func buildCourse(at courseURL: URL, coursesRoot: URL) -> Course {
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
            print("[CourseIndexer] Failed to list course dir \(courseURL.path): \(error)")
            return Course(
                folderName: folderName,
                title: title,
                coverFileName: coverFileName,
                tags: [],
                modules: []
            )
        }

        for entry in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let module = buildModule(at: entry, courseRoot: courseURL)
                if !module.items.isEmpty || true { // keep empty modules too — plan §9 is silent on this
                    modules.append(module)
                }
            } else if let type = itemType(for: entry) {
                let item = buildItem(at: entry, in: courseURL, type: type)
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

        // Overlay persisted progress (if any). A nil sidecar here
        // means "first time we see this course" — the UUID from
        // `fresh.id` will be persisted in `seedMissingSidecars` and
        // become stable from then on.
        guard let sidecar = SidecarStore.read(
            courseURL: courseURL,
            fileManager: fileManager
        ) else {
            return fresh
        }
        return SidecarStore.apply(sidecar, to: fresh)
    }

    /// Build a `Module` from a first-level subdirectory. Recursively
    /// collects recognized items below it.
    private func buildModule(at moduleURL: URL, courseRoot: URL) -> Module {
        let folderName = moduleURL.lastPathComponent
        let items = collectItems(in: moduleURL, courseRoot: courseRoot, currentlyRelativePath: folderName)
        return Module(
            folderName: folderName,
            title: folderName,
            items: items
        )
    }

    /// Recursive scan starting at `directory`. Returns items with their
    /// `relativePath` anchored at `courseRoot`, so e.g. a video at
    /// `course/01 Intro/sub/file.mp4` becomes relative path
    /// `01 Intro/sub/file.mp4`.
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
            print("[CourseIndexer] Failed to list module dir \(directory.path): \(error)")
            return []
        }

        var items: [CourseItem] = []
        for entry in contents.sorted(by: { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }) {
            let isDir = (try? entry.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                let nextRelative = "\(currentlyRelativePath)/\(entry.lastPathComponent)"
                items.append(contentsOf: collectItems(in: entry, courseRoot: courseRoot, currentlyRelativePath: nextRelative))
            } else if let type = itemType(for: entry) {
                let absoluteRelativePath = "\(currentlyRelativePath)/\(entry.lastPathComponent)"
                let item = buildItem(
                    at: entry,
                    in: courseRoot,
                    type: type,
                    relativePath: absoluteRelativePath
                )
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

    /// Map a file URL to an `ItemType`, or `nil` if it's not recognized.
    private func itemType(for url: URL) -> ItemType? {
        ItemType.from(extension: url.pathExtension)
    }

    /// Build a `CourseItem` for a single file. `relativePath` defaults
    /// to just the filename (used for items at the course root, which
    /// end up in the virtual `General` module).
    private func buildItem(
        at url: URL,
        in courseRoot: URL,
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

    /// Sequential AVAsset pass: for every video item across all courses,
    /// open it with `AVURLAsset` and read `.duration`. Errors on
    /// individual files are logged and `durationSeconds` stays nil.
    /// Concurrency note: we deliberately serialize this — Fase 2+ can
    /// parallelize if it ever shows up as a hotspot.
    private func prefetchVideoDurations(courses: [Course], coursesRoot: URL) async -> [Course] {
        var updated = courses
        for courseIndex in updated.indices {
            for moduleIndex in updated[courseIndex].modules.indices {
                for itemIndex in updated[courseIndex].modules[moduleIndex].items.indices
                where updated[courseIndex].modules[moduleIndex].items[itemIndex].type == .video
                {
                    let relativePath = updated[courseIndex].modules[moduleIndex].items[itemIndex].relativePath
                    let fileURL = coursesRoot
                        .appendingPathComponent(updated[courseIndex].folderName, isDirectory: true)
                        .appendingPathComponent(relativePath)
                    let duration = await loadDuration(for: fileURL)
                    updated[courseIndex].modules[moduleIndex].items[itemIndex].durationSeconds = duration
                }
            }
        }
        return updated
    }

    private func loadDuration(for url: URL) async -> Double? {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            guard duration.isValid, duration.isNumeric, duration.value > 0 else { return nil }
            return CMTimeGetSeconds(duration)
        } catch {
            print("[CourseIndexer] AVAsset duration load failed for \(url.lastPathComponent): \(error)")
            return nil
        }
    }
}
