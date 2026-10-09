// MacSettingsView.swift
//
// Standard macOS `Settings` scene. Exposed via `⌘,` so the user can
// reach it from anywhere in the app. Today it shows one field: the
// library root path.
//
// Plan §15.4 mentions port/Bonjour name as advanced options for Fase
// 11 — leaving them out here keeps the settings scope to "Fase 9
// surface area" only.

import AppKit
import Shared
import SwiftUI

struct MacSettingsView: View {
    @EnvironmentObject private var store: MacLibraryStore

    var body: some View {
        Form {
            Section {
                libraryPathRow
            } header: {
                Text("Biblioteca")
            } footer: {
                Text("La carpeta donde se guardan los cursos que vas a enviar a tu iPad o iPhone. Por defecto: ~/Movies/CursosIpad/.")
                    .font(.caption)
                    .foregroundStyle(Color.appInfo)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 220)
    }

    private var libraryPathRow: some View {
        HStack(spacing: 12) {
            Text(store.libraryURL.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Color.appTitle)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button("Elegir…") {
                chooseLibraryRoot()
            }
            Button("Por defecto") {
                store.libraryURL = MacSettings.defaultLibraryURL()
            }
        }
    }

    private func chooseLibraryRoot() {
        let panel = NSOpenPanel()
        panel.title = "Elige tu carpeta de biblioteca"
        panel.message = "Elige la carpeta raíz donde guardas tus cursos."
        panel.prompt = "Usar como biblioteca"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.directoryURL = store.libraryURL
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.libraryURL = url
    }
}