// MacCourseEditor.swift
//
// Replaces `MacCourseDetailView` (Fase 9). Top-of-window metadata
// editor + `HSplitView` with an outline pane (left) and a preview
// pane (right). Owns the `draftX` / `savedX` hydrate-and-dirty
// pattern for every editable field — title, description, tags —
// and the `save()` call that persists the buffer to the sidecar.
//
// The outline and preview are siblings: the editor passes the
// selected `CourseItem.ID` down to the outline and observes the
// `Course` from the store to know what the preview pane should
// show. There's no direct outline ↔ preview coupling.
//
// Local edits only flush to disk when the user clicks "Guardar"
// (or hits ⌘S). This is the same model iOS uses for its implicit
// "every change is committed immediately" — except on Mac we
// give the user an explicit undo boundary, which matters when a
// field is expensive (like a video frame extraction) or when the
// edit has real consequences (a rename orphans sidecar progress).

import AppKit
import Shared
import SwiftUI

struct MacCourseEditor: View {
    let courseID: Course.ID
    @EnvironmentObject private var store: MacLibraryStore

    /// Live `Course` from the store. `EnvironmentObject` already
    /// gives observation; we just look up the current snapshot on
    /// every render.
    private var course: Course? {
        store.courses.first(where: { $0.id == courseID })
    }

    /// Selection flows down to the outline. The preview pane reads
    /// it back via the store's `Course` (looking up the item by
    /// `ID` keeps the editor's `CourseItem?` resolution single-
    /// source-of-truth in the indexer, not here).
    @State private var selectedItemID: CourseItem.ID?

    // MARK: - Edit buffers

    @State private var draftTitle: String = ""
    @State private var draftDescription: String = ""
    @State private var draftTags: [String] = []
    @State private var savedTitle: String = ""
    @State private var savedDescription: String = ""
    @State private var savedTags: [String] = []
    @State private var pendingAlertMessage: String?

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
        .onAppear { hydrateFromCourse() }
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
        VStack(spacing: 0) {
            HSplitView {
                // Left column: scrollable metadata + outline stacked.
                VStack(spacing: 0) {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            heroSection(course: course)
                            Divider().background(Color.appDivider)
                            tagsSection
                            Divider().background(Color.appDivider)
                            metadataSection(course: course)
                            Divider().background(Color.appDivider)
                        }
                        .padding(20)
                        .frame(maxWidth: 520, alignment: .leading)
                    }
                    .frame(maxWidth: 520)
                    .background(Color.appBackground.opacity(0.4))

                    Divider()

                    MacCourseOutline(
                        course: course,
                        courseURL: MacCourseOperations.courseDirectoryURL(
                            for: course,
                            libraryRoot: store.libraryURL
                        ),
                        selectedItemID: $selectedItemID,
                        onItemChanged: { Task { await store.refresh() } }
                    )
                    .frame(minHeight: 220)
                }
                .frame(minWidth: 320, idealWidth: 420)

                // Right column: preview.
                MacItemPreview(
                    item: selectedItem(from: course),
                    courseURL: MacCourseOperations.courseDirectoryURL(
                        for: course,
                        libraryRoot: store.libraryURL
                    ),
                    onError: { pendingAlertMessage = $0 },
                    onItemChanged: { Task { await store.refresh() } }
                )
                .frame(minWidth: 360)
            }
            Divider().background(Color.appDivider)
            bottomActionBar(course: course)
        }
    }

    private func selectedItem(from course: Course) -> CourseItem? {
        guard let selectedItemID else { return nil }
        for module in course.modules {
            if let item = module.items.first(where: { $0.id == selectedItemID }) {
                return item
            }
        }
        return nil
    }

    // MARK: - Hero (cover + title)

    @ViewBuilder
    private func heroSection(course: Course) -> some View {
        HStack(alignment: .top, spacing: 20) {
            coverCard(for: course)
                .frame(width: 220, height: 124)
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Título")
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                    TextField("Título del curso", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 18, weight: .semibold))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Carpeta")
                        .font(.caption)
                        .foregroundStyle(Color.appInfo)
                    Text(course.folderName)
                        .font(.system(size: 12, design: .monospaced))
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
            Rectangle().fill(Color.appDivider)
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
                .font(.system(size: 56, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.9))
        )
    }

    // MARK: - Tags

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Etiquetas")
                .font(.caption)
                .foregroundStyle(Color.appInfo)
            TagChipField(tags: $draftTags)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.appBackground)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(Color.appDivider, lineWidth: 0.5)
                )
            Text("Separá las etiquetas con Enter o coma. Sirven para filtrar en la biblioteca del iPad.")
                .font(.system(size: 11))
                .foregroundStyle(Color.appInfo)
        }
    }

    // MARK: - Description + cover controls

    @ViewBuilder
    private func metadataSection(course: Course) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Descripción")
                .font(.caption)
                .foregroundStyle(Color.appInfo)

            // Plain multiline TextEditor — markdown rendering is
            // done by iOS in `CourseDescriptionView`; the textarea
            // here is for raw markdown the user is composing.
            TextEditor(text: $draftDescription)
                .font(.system(size: 13))
                .frame(minHeight: 96)
                .padding(6)
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
            Button("Descartar") { hydrateFromCourse() }
                .disabled(!isDirty)
            Button("Guardar") { save(course: course) }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!isDirty)
                .buttonStyle(.borderedProminent)
                .tint(Color.appMenu)
        }
    }

    // MARK: - Bottom action bar

    /// Fase 10 placeholder. The "Enviar al iPad" CTA is the home
    /// of the Fase 11 (WiFi transfer) sheet — for now it just
    /// shows a disabled button with a one-line explainer so the
    /// editor's bottom edge doesn't feel unfinished.
    @ViewBuilder
    private func bottomActionBar(course: Course) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(course.folderName)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(Color.appInfo)
                Text("\(course.totalItemCount) lección\(course.totalItemCount == 1 ? "" : "es") · \(MacFormat.bytes(course.allItems.reduce(Int64(0)) { $0 + $1.sizeBytes }))")
                    .font(.system(size: 11))
                    .foregroundStyle(Color.appInfo)
            }
            Spacer()
            Button {
                // Fase 11 — transfer sheet.
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "ipad.and.arrow.forward")
                    Text("Enviar al iPad")
                }
            }
            .disabled(true)
            .buttonStyle(.borderedProminent)
            .tint(Color.appMenu)
            .help("Disponible en la siguiente fase (transferencia por WiFi).")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(Color.appBackground.opacity(0.4))
    }

    // MARK: - Hydrate / dirty

    /// Push the live course values into the local edit buffers.
    /// Called whenever the selected course changes (or first
    /// appears) so the editor always starts from the persisted
    /// state.
    private func hydrateFromCourse() {
        guard let course else {
            draftTitle = ""
            draftDescription = ""
            draftTags = []
            savedTitle = ""
            savedDescription = ""
            savedTags = []
            return
        }
        // Post-Step-1, `course` carries `description` and `tags` from
        // the sidecar (via `SidecarStore.apply`), so we read from
        // the in-memory snapshot instead of `SidecarStore.read`
        // directly. This matches how `title` is hydrated.
        draftTitle = course.title
        draftDescription = course.description ?? ""
        draftTags = course.tags
        savedTitle = draftTitle
        savedDescription = draftDescription
        savedTags = draftTags
    }

    private func isDraftDirty(course: Course) -> Bool {
        draftTitle != savedTitle
            || draftDescription != savedDescription
            || draftTags != savedTags
    }

    // MARK: - Save / cover

    private func save(course: Course) {
        Task {
            let ok = await MacCourseOperations.persistCourseMetadata(
                course,
                libraryRoot: store.libraryURL,
                title: draftTitle,
                description: draftDescription.isEmpty ? nil : draftDescription,
                coverFileName: course.coverFileName,
                tags: draftTags
            )
            if ok {
                savedTitle = draftTitle
                savedDescription = draftDescription
                savedTags = draftTags
                await store.refresh()
            } else {
                pendingAlertMessage = "No se pudo guardar el sidecar. Revisa la consola para más detalles."
            }
        }
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
        Task {
            let url = await MacCourseOperations.autoDetectCoverImproved(for: courseURL)
            if url == nil {
                pendingAlertMessage = "No hay imágenes ni videos en el curso. Probá con otra carpeta."
                return
            }
            await store.refresh()
        }
    }

    // MARK: - Missing-course placeholder

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
