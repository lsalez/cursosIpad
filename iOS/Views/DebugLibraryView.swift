// DebugLibraryView.swift
//
// Fase 1 deliverable: list courses found in `Documents/`. Real
// library UI lands in Fase 2 (grid, palettes, tags filter, etc.) — what
// sits here is enough to prove the indexer works end-to-end.
//
// This view creates a fresh `CourseIndexer` per instantiation; Fase 2
// will hoist the indexer to a shared state object so the Library and
// the Detail views see the same data.

import Shared
import SwiftUI

struct DebugLibraryView: View {
    @State private var courses: [Course] = []
    @State private var scanError: String?
    @State private var isScanning = false

    private let indexer = CourseIndexer()

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("cursosIpad")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(action: { Task { await rescan() } }) {
                            Label("Re-escanear", systemImage: "arrow.clockwise")
                        }
                        .disabled(isScanning)
                    }
                }
                .task { await rescan() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if isScanning && courses.isEmpty {
            ProgressView("Escaneando…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if courses.isEmpty {
            ContentUnavailableView(
                "Aún no hay cursos",
                systemImage: "books.vertical",
                description: Text(
                    "Agrega una carpeta en **Documentos › cursosIpad** desde la app Archivos. " +
                    "La app la detectará al reabrir."
                )
            )
        } else {
            List(courses) { course in
                courseRow(course)
            }
            .listStyle(.insetGrouped)
        }
    }

    @ViewBuilder
    private func courseRow(_ course: Course) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(course.title)
                .font(.headline)
            Text("\(course.modules.count) módulos · \(course.totalItemCount) archivos")
                .font(.caption)
                .foregroundStyle(.secondary)
            if !course.tags.isEmpty {
                Text(course.tags.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 4)
    }

    private func rescan() async {
        isScanning = true
        defer { isScanning = false }
        do {
            courses = try await indexer.index()
            scanError = nil
        } catch {
            scanError = "\(error)"
            courses = []
        }
    }
}
