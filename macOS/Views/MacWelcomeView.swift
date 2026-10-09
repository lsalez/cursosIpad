// MacWelcomeView.swift
//
// First-launch placeholder for the Mac app. Plan §15.1 mentions a
// welcome / empty state for the library; this view is that state.
// Renders:
//
//   * The cursosIpad wordmark.
//   * A short explainer copy in Spanish ("Aún no tienes cursos en tu
//     biblioteca. Importa una carpeta desde tu Mac o elige tu carpeta
//     de cursos en Preferencias.").
//   * Two buttons: "Importar curso…" (open NSOpenPanel) and "Elegir
//     carpeta de biblioteca…" (open NSOpenPanel for the library root,
//     also routed via Preferences later).
//
// Unlike the iOS Welcome (`iOS/Views/Welcome/WelcomeView.swift`),
// this isn't gated by an `@AppStorage("hasSeenWelcome")` flag — the
// Mac app's main window is the library, and an empty library looks
// exactly like this view. The Mac user can fill the library any time;
// there's no onboarding carousel that needs to be dismissed first.

import AppKit
import Shared
import SwiftUI

struct MacWelcomeView: View {
    @EnvironmentObject private var store: MacLibraryStore
    let onCourseImported: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "books.vertical.fill")
                .font(.system(size: 72, weight: .light))
                .foregroundStyle(Color.appMenu)
            VStack(spacing: 8) {
                Text("cursosIpad")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.appTitle)
                Text(emptyCopy)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appInfo)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .fixedSize(horizontal: false, vertical: true)
            }
            VStack(spacing: 12) {
                Button("Importar curso…") {
                    importCourse()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .tint(Color.appMenu)

                Button("Elegir carpeta de biblioteca…") {
                    chooseLibraryRoot()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
            }
            .padding(.horizontal, 24)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var emptyCopy: String {
        if MacCourseOperations.imageCandidates(
            at: MacCourseOperations.courseDirectoryURL(
                for: Course(folderName: "_unused", title: ""),
                libraryRoot: store.libraryURL
            )
        ).isEmpty {
            return "Tu biblioteca está vacía. Importa una carpeta de curso desde tu Mac, o elige una carpeta de biblioteca con cursos ya organizados."
        }
        return "Tu biblioteca está vacía. Importa una carpeta de curso desde tu Mac para empezar."
    }

    private func importCourse() {
        guard let imported = MacCourseOperations.showImportPanel(
            into: store.libraryURL
        ) else { return }
        print("[MacWelcomeView] Imported course folder: \(imported.path)")
        onCourseImported()
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