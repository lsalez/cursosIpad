// MacLibrarySidebar.swift
//
// The sidebar shown on the leading edge of `NavigationSplitView` in
// the macOS app. Lists every course in the library root with cover
// thumbnail + title + a small summary line (item count + total size).
//
// The selection binding lives on the parent (`CursosIpadMacApp`'s
// root scene) so the same selection drives the detail column across
// re-renders. The sidebar doesn't own it.
//
// A small "Importar…" toolbar lives at the top so the user can add a
// course without going through Settings.

import Shared
import SwiftUI

struct MacLibrarySidebar: View {
    @EnvironmentObject private var store: MacLibraryStore
    @Binding var selection: Course.ID?

    var body: some View {
        List(selection: $selection) {
            Section {
                if store.courses.isEmpty {
                    Text("Sin cursos")
                        .foregroundStyle(Color.appInfo)
                        .font(.subheadline)
                        .padding(.vertical, 8)
                } else {
                    ForEach(store.courses) { course in
                        sidebarRow(course)
                            .tag(Optional(course.id))
                    }
                }
            } header: {
                HStack {
                    Text("Cursos")
                    Spacer()
                    if store.isLoading {
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    importCourse()
                } label: {
                    Label("Importar curso", systemImage: "square.and.arrow.down")
                }
                .help("Importar una carpeta de curso")
            }
            ToolbarItem(placement: .automatic) {
                Button {
                    Task { await store.refresh() }
                } label: {
                    Label("Re-escanear", systemImage: "arrow.clockwise")
                }
                .help("Re-escanear la carpeta de biblioteca")
            }
        }
    }

    @ViewBuilder
    private func sidebarRow(_ course: Course) -> some View {
        let summary = courseSummary(for: course)
        HStack(alignment: .center, spacing: 10) {
            coverThumbnail(for: course)
                .frame(width: 40, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(course.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.appTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                Text(summary)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInfo)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    /// 16:9 thumbnail with a colored fallback when the course has no
    /// cover file. Mirrors the iOS `CourseCardView` placeholder shape.
    @ViewBuilder
    private func coverThumbnail(for course: Course) -> some View {
        let coverURL = MacCourseOperations.coverURL(for: course, libraryRoot: store.libraryURL)
        ZStack {
            Rectangle()
                .fill(Color.appDivider)
            if let coverURL,
               let image = NSImage(contentsOf: coverURL) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                LinearGradient(
                    colors: [
                        MacCoverColorExtractor.dominantColor(of: coverURL)
                            ?? Color.appAccentFallback,
                        Color.appMenu.opacity(0.7),
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            }
        }
    }

    /// "N lecciones · 234 MB" or similar. Size is in human units;
    /// rounded to 2 decimals so a 4 KB file shows as "0 MB" rather
    /// than being noise.
    private func courseSummary(for course: Course) -> String {
        let count = course.totalItemCount
        let lessonLabel = count == 1 ? "lección" : "lecciones"
        let totalBytes = course.allItems.reduce(Int64(0)) { $0 + $1.sizeBytes }
        let sizeLabel = MacFormat.bytes(totalBytes)
        return "\(count) \(lessonLabel) · \(sizeLabel)"
    }

    private func importCourse() {
        guard MacCourseOperations.showImportPanel(into: store.libraryURL) != nil else {
            return
        }
        Task { await store.refresh() }
    }
}

/// Tiny formatter helper. Lives here (instead of in a global
/// extension) because it only matters to the sidebar's summary line.
enum MacFormat {
    static func bytes(_ value: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB, .useKB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: value)
    }
}