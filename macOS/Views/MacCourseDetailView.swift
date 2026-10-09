// MacCourseDetailView.swift
//
// The detail column shown on the right side of
// `NavigationSplitView`. Hosts the editing UI for the course the
// sidebar selects: title, description, cover, and the module/item
// tree (read-only in Fase 9 — Fase 10 makes it editable).
//
// Edits are kept in local `@State` until the user clicks "Guardar".
// This keeps the contract with the sidebar simple ("your selection is
// stable until you switch courses") and avoids racing writes while
// the user is mid-edit. The save call writes to the sidecar and then
// asks the store to re-scan so the in-memory `Course` picks up the
// persisted values.
//
// The view is bound to a `Course.ID` rather than a `Course` value —
// the parent (`RootView`) reads the latest `Course` from the store
// on every render, so cover/title edits show up live once the user
// hits save.

import AppKit
import Shared
import SwiftUI

struct MacCourseDetailView: View {
    let courseID: Course.ID
    @EnvironmentObject private var store: MacLibraryStore

    /// Live `Course` from the store. `EnvironmentObject` already gives
    /// us observation; we just look up the current snapshot.
    private var course: Course? {
        store.courses.first(where: { $0.id == courseID })
    }

    /// Local edit buffer. Cleared every time the user switches to a
    /// different course (see `onChange(of: courseID)`).
    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var pendingAlertMessage: String?

    /// Last-saved snapshot of the editable fields. Used to detect
    /// "is the draft dirty?" so the "Guardar" button can be enabled
    /// or disabled accordingly. Cleared alongside `draft*` when the
    /// course changes.
    @State private var savedTitle: String = ""
    @State private var savedDescription: String = ""

    var body: some View {
        Group {
            if let course {
                editor(for: course)
            } else {
                missingCoursePlaceholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
        .onChange(of: courseID) { _, _ in
            hydrateFromCourse()
        }
        .onAppear {
            hydrateFromCourse()
        }
        .alert(
            "Aviso",
            isPresented: Binding(
                get: { pendingAlertMessage != nil },
                set: { if !$0 { pendingAlertMessage = nil } }
            ),
            presenting: pendingAlertMessage
        ) { _ in
            Button("OK", role: .cancel) { pendingAlertMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Editor body

    @ViewBuilder
    private func editor(for course: Course) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                heroSection(course: course)
                Divider()
                    .background(Color.appDivider)
                metadataSection(course: course)
                Divider()
                    .background(Color.appDivider)
                modulesSection(course: course)
            }
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .top)
    }

    // MARK: - Hero (cover + title)

    @ViewBuilder
    private func heroSection(course: Course) -> some View {
        HStack(alignment: .top, spacing: 24) {
            coverCard(for: course)
                .frame(width: 240, height: 135)
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Título")
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                    TextField(
                        "Título del curso",
                        text: $draftTitle
                    )
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 20, weight: .semibold))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Carpeta")
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                    Text(course.folderName)
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(Color.appInfo)
                        .textSelection(.enabled)
                }

                saveBar(course: course)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func coverCard(for course: Course) -> some View {
        let url = MacCourseOperations.coverURL(for: course, libraryRoot: store.libraryURL)
        ZStack {
            Rectangle()
                .fill(Color.appDivider)
            if let url, let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                placeholderCover(for: course)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.appDivider, lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private func placeholderCover(for course: Course) -> some View {
        let initial = course.title.first.map { String($0).uppercased() } ?? "·"
        let tint = MacCoverColorExtractor.dominantColor(
            of: MacCourseOperations.coverURL(for: course, libraryRoot: store.libraryURL)
        ) ?? Color.appAccentFallback
        LinearGradient(
            colors: [tint.opacity(0.85), tint.opacity(0.55)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .overlay(
            Text(initial)
                .font(.system(size: 60, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        )
    }

    // MARK: - Metadata (description + cover controls)

    @ViewBuilder
    private func metadataSection(course: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Descripción")
                .font(.caption)
                .foregroundStyle(Color.appInfo)

            // Plain multiline TextEditor — no fancy markdown rendering
            // here, the Mac editor's textarea is for raw markdown that
            // iOS will render in Fase 10 (plan §14.5 description tab).
            TextEditor(text: $draftDescription)
                .font(.system(size: 13))
                .frame(minHeight: 120)
                .padding(8)
                .background(Color.appBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.appDivider, lineWidth: 0.5)
                )

            HStack(spacing: 12) {
                Button("Elegir imagen…") {
                    pickCover(course: course)
                }
                Button("Auto-detectar") {
                    autoDetectCover(course: course)
                }
                Spacer()
            }
        }
    }

    // MARK: - Modules (read-only in Fase 9)

    @ViewBuilder
    private func modulesSection(course: Course) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Contenido")
                .font(.caption)
                .foregroundStyle(Color.appInfo)

            if course.modules.isEmpty {
                Text("Esta carpeta no contiene videos, PDFs ni HTMLs.")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.appInfo)
                    .padding(.vertical, 8)
            } else {
                ForEach(course.modules) { module in
                    moduleBlock(module)
                }
            }

            Text("La edición de módulos (drag & drop, renombrar, eliminar) llega en la Fase 10.")
                .font(.caption)
                .foregroundStyle(Color.appInfo)
                .padding(.top, 8)
        }
    }

    @ViewBuilder
    private func moduleBlock(_ module: Module) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "folder")
                    .foregroundStyle(Color.appInfo)
                Text(module.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.appTitle)
                Spacer()
                Text("\(module.items.count)")
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appInfo)
            }
            if !module.items.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(module.items) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.type.iconSystemName)
                                .foregroundStyle(Color.appInfo)
                                .frame(width: 16)
                            Text(item.title)
                                .font(.system(size: 13))
                                .foregroundStyle(Color.appTitle)
                                .lineLimit(1)
                            Spacer()
                            Text(MacFormat.bytes(item.sizeBytes))
                                .font(.system(size: 11))
                                .foregroundStyle(Color.appInfo)
                        }
                    }
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(Color.appBackground.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    // MARK: - Save bar

    @ViewBuilder
    private func saveBar(course: Course) -> some View {
        let isDirty = isDraftDirty(course: course)
        HStack {
            if isDirty {
                Text("Cambios sin guardar")
                    .font(.caption)
                    .foregroundStyle(Color.appInfo)
            }
            Spacer()
            Button("Descartar") {
                hydrateFromCourse()
            }
            .disabled(!isDirty)
            Button("Guardar") {
                save(course: course)
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!isDirty)
            .buttonStyle(.borderedProminent)
            .tint(Color.appMenu)
        }
    }

    // MARK: - Actions

    /// Push the live course values into the local edit buffers. Called
    /// whenever the selected course changes (or first appears) so the
    /// editor always starts from the persisted state.
    private func hydrateFromCourse() {
        guard let course else {
            draftTitle = ""
            draftDescription = ""
            savedTitle = ""
            savedDescription = ""
            return
        }
        let sidecar = readSidecar(for: course)
        draftTitle = sidecar?.title ?? course.title
        draftDescription = sidecar?.description ?? ""
        savedTitle = draftTitle
        savedDescription = draftDescription
    }

    /// Returns `true` when at least one editable field differs from
    /// the last-saved snapshot. Drives the Save/Discard button state.
    private func isDraftDirty(course: Course) -> Bool {
        let sidecar = readSidecar(for: course)
        let savedT = sidecar?.title ?? course.title
        let savedD = sidecar?.description ?? ""
        return draftTitle != savedT || draftDescription != savedD
    }

    /// Read the sidecar for `course`, if any. Used both for hydration
    /// and dirty-detection so we always compare against the persisted
    /// truth, not the in-memory `Course` (whose title/cover/description
    /// may not yet reflect Mac edits per plan §5 contract boundary).
    private func readSidecar(for course: Course) -> Sidecar? {
        let url = MacCourseOperations.courseDirectoryURL(for: course, libraryRoot: store.libraryURL)
        return SidecarStore.read(courseURL: url)
    }

    private func save(course: Course) {
        let courseURL = MacCourseOperations.courseDirectoryURL(for: course, libraryRoot: store.libraryURL)
        Task {
            let ok = await MacCourseOperations.persistCourseMetadata(
                course,
                libraryRoot: store.libraryURL,
                title: draftTitle,
                description: draftDescription.isEmpty ? nil : draftDescription,
                coverFileName: course.coverFileName,
                tags: nil
            )
            if ok {
                savedTitle = draftTitle
                savedDescription = draftDescription
                await store.refresh()
            } else {
                pendingAlertMessage = "No se pudo guardar el sidecar. Revisa la consola para más detalles."
            }
        }
        _ = courseURL
    }

    private func pickCover(course: Course) {
        guard let imageURL = MacCourseOperations.showCoverPanel() else { return }
        let courseURL = MacCourseOperations.courseDirectoryURL(for: course, libraryRoot: store.libraryURL)
        guard MacCourseOperations.setCover(from: imageURL, for: courseURL) else {
            pendingAlertMessage = "No se pudo copiar la imagen a la carpeta del curso."
            return
        }
        Task { await store.refresh() }
    }

    private func autoDetectCover(course: Course) {
        let courseURL = MacCourseOperations.courseDirectoryURL(for: course, libraryRoot: store.libraryURL)
        guard MacCourseOperations.autoDetectCover(for: courseURL) != nil else {
            pendingAlertMessage = "No hay imágenes en la raíz del curso para usar como portada."
            return
        }
        Task { await store.refresh() }
    }

    // MARK: - Missing course placeholder

    private var missingCoursePlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Curso no disponible")
                .font(.headline)
                .foregroundStyle(Color.appTitle)
            Text("Este curso ya no está en la biblioteca. Vuelve a la lista para re-escanear.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - ItemType → SF Symbol

private extension ItemType {
    var iconSystemName: String {
        switch self {
        case .video: return "play.rectangle"
        case .pdf: return "doc.richtext"
        case .html: return "doc.plaintext"
        }
    }
}