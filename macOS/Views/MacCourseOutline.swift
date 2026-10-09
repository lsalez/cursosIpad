// MacCourseOutline.swift
//
// Tree of modules and items for the Mac course editor. Renders
// inside the editor's left column below the metadata block. Owns:
//
//   * Selection (so the preview pane can show the highlighted item).
//   * Drag & drop with a private `Transferable` (cross-module
//     moves use `dropDestination` on each Section; within-module
//     reorders use `.onMove`).
//   * Inline rename via a TextField overlay. Uniqueness is checked
//     against siblings before commit; a warning alert (per Fase 5
//     contract — see `Sidecar.swift:29-32`) interrupts the rename
//     to confirm the progress orphan.
//   * Context menu: Renombrar / Eliminar. Delete confirms with
//     the full path; uses `FileManager.trashItem` so the file is
//     recoverable from the macOS Trash.
//
// All mutations are funneled through `MacCourseOperations` static
// methods; the parent (the editor) calls `store.refresh()` after
// `onItemChanged` fires so the on-disk rename / move / trash is
// reflected in the next index.
//
// Reorder persistence: the indexer sorts by
// `localizedStandardCompare`, so the on-disk sort is the source of
// truth. Drag-to-reorder renames the file / folder with a
// `01-, 02-, 03-…` prefix that the indexer picks up. If the
// desired slot is already taken, the prefix is bumped up — the
// user can manually clean up if they want a strict sequence.

import AppKit
import Shared
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Transferable payload

/// Payload for drag & drop within the outline. Identifies a single
/// node (module or item) by its stable `id`. Modules and items
/// share the `UUID` namespace (both `Module.id` and
/// `CourseItem.id` are UUIDs), so a single `id` field is enough
/// and the `kind` discriminator is just for sanity.
struct OutlineTransfer: Codable, Transferable {
    enum Kind: String, Codable { case module, item }
    let kind: Kind
    let id: UUID

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .outlineTransfer)
    }
}

extension UTType {
    /// Private UTType for outline drag & drop. Exported under our
    /// bundle id so other apps on the system can't accidentally
    /// accept our drops.
    static let outlineTransfer = UTType(exportedAs: "mx.salez.cursosipad.outlinetransfer")
}

// MARK: - Outline view

struct MacCourseOutline: View {
    let course: Course
    let courseURL: URL
    @Binding var selectedItemID: CourseItem.ID?
    let onItemChanged: () -> Void

    // MARK: UI state

    @State private var renamingTarget: RenameTarget?
    @State private var renameDraft: String = ""
    @State private var pendingDelete: DeleteTarget?
    @State private var pendingRenameOrphan: RenameOrphanTarget?
    @State private var pendingAlert: String?
    @FocusState private var renameFieldFocused: Bool

    // MARK: Targets (Identifiable for alerts / sheets)

    enum RenameTarget: Identifiable {
        case module(folderName: String, displayName: String)
        case item(relativePath: String, displayName: String)
        var id: String {
            switch self {
            case .module(let n, _): return "module:\(n)"
            case .item(let p, _): return "item:\(p)"
            }
        }
    }

    enum DeleteTarget: Identifiable {
        case module(folderName: String, displayName: String)
        case item(relativePath: String, displayName: String)
        var id: String {
            switch self {
            case .module(let n, _): return "module:\(n)"
            case .item(let p, _): return "item:\(p)"
            }
        }
    }

    enum RenameOrphanTarget: Identifiable {
        case module(folderName: String, newName: String, affectedItems: Int)
        case item(relativePath: String, newName: String)
        var id: String {
            switch self {
            case .module(let n, _, _): return "module:\(n)"
            case .item(let p, _): return "item:\(p)"
            }
        }
    }

    // MARK: - Body

    var body: some View {
        List(selection: $selectedItemID) {
            ForEach(course.modules) { module in
                Section {
                    ForEach(module.items) { item in
                        itemRow(module: module, item: item)
                            .draggable(OutlineTransfer(kind: .item, id: item.id))
                    }
                    .onMove { source, destination in
                        reorderItemsIn(module: module, source: source, destination: destination)
                    }
                } header: {
                    moduleHeader(module: module)
                }
                .dropDestination(for: OutlineTransfer.self) { transfers, _ in
                    handleCrossModuleDrop(into: module, transfers: transfers)
                }
            }
            .onMove { source, destination in
                reorderModules(source: source, destination: destination)
            }
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.opacity(0.3))

        // Delete confirmation.
        .confirmationDialog(
            deleteTitle,
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { target in
            Button("Eliminar", role: .destructive) {
                commitDelete(target)
            }
            Button("Cancelar", role: .cancel) { pendingDelete = nil }
        } message: { target in
            Text(deleteMessage(for: target))
        }

        // Rename-orphan warning.
        .alert(
            "Renombrar borra el progreso",
            isPresented: Binding(
                get: { pendingRenameOrphan != nil },
                set: { if !$0 { pendingRenameOrphan = nil } }
            ),
            presenting: pendingRenameOrphan
        ) { target in
            Button("Cancelar", role: .cancel) {
                pendingRenameOrphan = nil
                renamingTarget = nil
            }
            Button("Renombrar", role: .destructive) {
                commitRenameAfterOrphanWarning(target)
            }
        } message: { target in
            Text(orphanMessage(for: target))
        }

        // Generic error alert.
        .alert(
            "Aviso",
            isPresented: Binding(
                get: { pendingAlert != nil },
                set: { if !$0 { pendingAlert = nil } }
            ),
            presenting: pendingAlert
        ) { _ in
            Button("OK", role: .cancel) { pendingAlert = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Module header

    @ViewBuilder
    private func moduleHeader(module: Module) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "folder")
                .foregroundStyle(Color.appInfo)
            if renamingTarget?.id == "module:\(module.folderName)" {
                TextField("Nombre del módulo", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($renameFieldFocused)
                    .onSubmit { commitModuleRename(module: module) }
                    .onExitCommand { cancelRename() }
            } else {
                Text(module.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.appTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) {
                        beginModuleRename(module: module)
                    }
            }
            Spacer()
            Text("\(module.items.count)")
                .font(.system(size: 11))
                .foregroundStyle(Color.appInfo)
        }
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .contextMenu {
            Button("Renombrar") { beginModuleRename(module: module) }
            Button("Eliminar", role: .destructive) {
                pendingDelete = .module(
                    folderName: module.folderName,
                    displayName: module.title
                )
            }
        }
        .draggable(OutlineTransfer(kind: .module, id: module.id))
    }

    // MARK: - Item row

    @ViewBuilder
    private func itemRow(module: Module, item: CourseItem) -> some View {
        let isSelected = selectedItemID == item.id
        HStack(spacing: 8) {
            Image(systemName: item.type.iconSystemName)
                .foregroundStyle(Color.appInfo)
                .frame(width: 16)
            if renamingTarget?.id == "item:\(item.relativePath)" {
                TextField("Nombre del archivo", text: $renameDraft)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .focused($renameFieldFocused)
                    .onSubmit { commitItemRename(item: item) }
                    .onExitCommand { cancelRename() }
            } else {
                Text(item.title)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.appTitle)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .onTapGesture(count: 2) {
                        beginItemRename(item: item)
                    }
            }
            Spacer()
            Text(MacFormat.bytes(item.sizeBytes))
                .font(.system(size: 11))
                .foregroundStyle(Color.appInfo)
        }
        .padding(.vertical, 1)
        .padding(.leading, 8)
        .contentShape(Rectangle())
        .tag(Optional(item.id))
        .listRowBackground(isSelected ? Color.appMenu.opacity(0.15) : Color.clear)
        .contextMenu {
            Button("Renombrar") { beginItemRename(item: item) }
            Button("Eliminar", role: .destructive) {
                pendingDelete = .item(
                    relativePath: item.relativePath,
                    displayName: item.title
                )
            }
        }
    }

    // MARK: - Reorder handlers

    private func reorderItemsIn(
        module: Module,
        source: IndexSet,
        destination: Int
    ) {
        guard let sourceIndex = source.first else { return }
        // SwiftUI's `destination` is the post-move insertion index
        // in the post-move array. When moving down, subtract 1
        // because the source row is still counted.
        let newIndex = destination > sourceIndex ? destination - 1 : destination
        guard newIndex != sourceIndex else { return }
        let item = module.items[sourceIndex]
        _ = MacCourseOperations.reorderItemInPlace(
            at: item.relativePath,
            toIndex: newIndex,
            in: courseURL
        )
        onItemChanged()
    }

    private func reorderModules(source: IndexSet, destination: Int) {
        guard let sourceIndex = source.first else { return }
        let newIndex = destination > sourceIndex ? destination - 1 : destination
        guard newIndex != sourceIndex else { return }
        let module = course.modules[sourceIndex]
        _ = MacCourseOperations.reorderModule(
            folderName: module.folderName,
            toIndex: newIndex,
            in: courseURL
        )
        onItemChanged()
    }

    private func handleCrossModuleDrop(
        into destinationModule: Module,
        transfers: [OutlineTransfer]
    ) -> Bool {
        guard let transfer = transfers.first, transfer.kind == .item else {
            return false
        }
        guard let item = findItem(byID: transfer.id) else { return false }
        // If the drop target is the item's current module, the
        // user is just re-sorting within the module — let `.onMove`
        // handle that. We only act on real cross-module moves.
        guard item.relativePath.hasPrefix(destinationModule.folderName + "/") == false else {
            return false
        }
        let moved = MacCourseOperations.moveItemToModule(
            from: item.relativePath,
            toFolder: destinationModule.folderName,
            in: courseURL
        )
        if moved == nil {
            pendingAlert = "No se pudo mover el archivo. ¿Ya existe un archivo con ese nombre en el módulo de destino?"
            return false
        }
        onItemChanged()
        return true
    }

    // MARK: - Rename handlers

    private func beginModuleRename(module: Module) {
        renamingTarget = .module(folderName: module.folderName, displayName: module.title)
        renameDraft = module.folderName
        renameFieldFocused = true
    }

    private func beginItemRename(item: CourseItem) {
        renamingTarget = .item(relativePath: item.relativePath, displayName: item.title)
        renameDraft = (item.relativePath as NSString).lastPathComponent
        renameFieldFocused = true
    }

    private func cancelRename() {
        renamingTarget = nil
        renameDraft = ""
        renameFieldFocused = false
    }

    private func commitModuleRename(module: Module) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            pendingAlert = "El nombre no puede estar vacío."
            cancelRename()
            return
        }
        let siblings = course.modules
            .map(\.folderName)
            .filter { $0 != module.folderName }
        guard MacCourseOperations.validateUnique(name: trimmed, in: siblings) else {
            pendingAlert = "Ya existe otro módulo con ese nombre."
            return
        }
        guard trimmed != module.folderName else { cancelRename(); return }
        let affected = module.items.count
        pendingRenameOrphan = .module(
            folderName: module.folderName,
            newName: trimmed,
            affectedItems: affected
        )
    }

    private func commitItemRename(item: CourseItem) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            pendingAlert = "El nombre no puede estar vacío."
            cancelRename()
            return
        }
        let parent = (item.relativePath as NSString).deletingLastPathComponent
        let siblings = itemSiblings(in: parent, excluding: item.relativePath)
        guard MacCourseOperations.validateUnique(name: trimmed, in: siblings) else {
            pendingAlert = "Ya existe otro archivo con ese nombre en este módulo."
            return
        }
        guard trimmed != (item.relativePath as NSString).lastPathComponent else {
            cancelRename()
            return
        }
        pendingRenameOrphan = .item(
            relativePath: item.relativePath,
            newName: trimmed
        )
    }

    private func commitRenameAfterOrphanWarning(_ target: RenameOrphanTarget) {
        switch target {
        case .module(let oldName, let newName, _):
            let result = MacCourseOperations.renameModule(
                at: oldName,
                to: newName,
                in: courseURL
            )
            if result == nil {
                pendingAlert = "No se pudo renombrar el módulo. Revisa la consola para más detalles."
            }
        case .item(let oldPath, let newName):
            let result = MacCourseOperations.renameItem(
                at: oldPath,
                to: newName,
                in: courseURL
            )
            if result == nil {
                pendingAlert = "No se pudo renombrar el archivo. Revisa la consola para más detalles."
            }
        }
        pendingRenameOrphan = nil
        renamingTarget = nil
        renameDraft = ""
        renameFieldFocused = false
        onItemChanged()
    }

    // MARK: - Delete

    private var deleteTitle: String {
        switch pendingDelete {
        case .module: "Eliminar módulo"
        case .item: "Eliminar archivo"
        case nil: ""
        }
    }

    private func deleteMessage(for target: DeleteTarget) -> String {
        switch target {
        case .module(let folderName, let displayName):
            return "“\(displayName)” y todos sus archivos se moverán a la Papelera.\n\nRuta: \(courseURL.path)/\(folderName)"
        case .item(let relativePath, let displayName):
            return "“\(displayName)” se moverá a la Papelera.\n\nRuta: \(courseURL.path)/\(relativePath)"
        }
    }

    private func commitDelete(_ target: DeleteTarget) {
        switch target {
        case .module(let folderName, _):
            let ok = MacCourseOperations.trashModule(folderName: folderName, in: courseURL)
            if !ok {
                pendingAlert = "No se pudo mover el módulo a la Papelera. Revisa la consola para más detalles."
            }
        case .item(let relativePath, _):
            let ok = MacCourseOperations.trashItem(at: relativePath, in: courseURL)
            if !ok {
                pendingAlert = "No se pudo mover el archivo a la Papelera. Revisa la consola para más detalles."
            }
        }
        pendingDelete = nil
        // Clear the selection if the deleted item was selected.
        if case .item(let path, _) = target,
           let item = findItem(byRelativePath: path),
           selectedItemID == item.id {
            selectedItemID = nil
        }
        onItemChanged()
    }

    // MARK: - Orphan message copy

    private func orphanMessage(for target: RenameOrphanTarget) -> String {
        switch target {
        case .module(_, let newName, let affected):
            return "Renombrar este módulo a “\(newName)” hará que se pierda el progreso visto de sus \(affected) lección\(affected == 1 ? "" : "es")."
        case .item(_, let newName):
            return "Renombrar este archivo a “\(newName)” hará que se pierda el progreso visto de la lección."
        }
    }

    // MARK: - Lookups

    private func findItem(byID id: UUID) -> CourseItem? {
        for module in course.modules {
            if let item = module.items.first(where: { $0.id == id }) {
                return item
            }
        }
        return nil
    }

    private func findItem(byRelativePath path: String) -> CourseItem? {
        for module in course.modules {
            if let item = module.items.first(where: { $0.relativePath == path }) {
                return item
            }
        }
        return nil
    }

    /// Filenames of items that live in the same module folder as
    /// `excludePath`. Used by the rename uniqueness check to know
    /// who counts as a "sibling" for the new name.
    private func itemSiblings(in folderName: String, excluding excludePath: String) -> [String] {
        let module = course.modules.first { $0.folderName == folderName }
            ?? course.modules.first { $0.folderName == "" } // General module
        return module?.items
            .map { ($0.relativePath as NSString).lastPathComponent }
            .filter { $0 != (excludePath as NSString).lastPathComponent } ?? []
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
