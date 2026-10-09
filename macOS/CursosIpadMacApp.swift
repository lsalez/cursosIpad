// CursosIpadMacApp.swift
//
// Entry point for the macOS companion app.
//
// Two scenes:
//   * `WindowGroup` — the main library window. Hosts a
//     `NavigationSplitView` with the course list in the sidebar and
//     the editor in the detail column. When the library is empty,
//     the detail column shows the `MacWelcomeView` so the user has
//     somewhere to land after first launch.
//   * `Settings` — the standard macOS Preferences window. Reachable
//     via `⌘,`. Hosts the library-root picker.
//
// The `MacLibraryStore` lives at the `WindowGroup` level so the
// selection survives the user opening / closing the settings window
// and so a `task { await store.refresh() }` runs once on first
// appearance without having to be redone in the settings scene.
//
// Per plan §15.1 the empty state shows an "Importar" affordance;
// that's `MacWelcomeView`, which the detail column swaps in when
// `store.courses.isEmpty` after the initial refresh completes.

import Shared
import SwiftUI

@main
struct CursosIpadMacApp: App {
    /// Shared library state. One store for the whole app — the
    /// Settings scene and the main window both read it via
    /// `@EnvironmentObject`, and the sidebar's import action
    /// mutates the same store the detail column watches.
    @StateObject private var library = MacLibraryStore()

    var body: some Scene {
        WindowGroup("Cursos") {
            RootScene()
                .environmentObject(library)
                .frame(minWidth: 720, minHeight: 480)
                .task {
                    await library.refresh()
                }
        }
        .windowResizability(.contentSize)

        Settings {
            MacSettingsView()
                .environmentObject(library)
        }
    }
}

/// Top-level container for the main window. The shape mirrors the
/// iOS `RootView` (sidebar + detail) but with `Course.ID` selection
/// (UUID) instead of `Course?` so the sidebar row's `.tag(...)` and
/// `List(selection:)` line up.
private struct RootScene: View {
    @EnvironmentObject private var library: MacLibraryStore
    @State private var selection: Course.ID?

    var body: some View {
        NavigationSplitView {
            MacLibrarySidebar(selection: $selection)
                .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 360)
        } detail: {
            if library.courses.isEmpty && !library.isLoading {
                MacWelcomeView {
                    // After an import, the sidebar refreshes its
                    // own snapshot. Force-refresh here too so the
                    // empty state disappears the moment the import
                    // succeeds even if the sidebar's own refresh
                    // hasn't kicked yet.
                    Task { await library.refresh() }
                }
            } else if let selectionID = selection,
                      library.courses.contains(where: { $0.id == selectionID }) {
                MacCourseEditor(courseID: selectionID)
            } else {
                selectionPlaceholder
            }
        }
        .background(Color.appBackground.ignoresSafeArea())
    }

    private var selectionPlaceholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Selecciona un curso")
                .font(.title3.bold())
                .foregroundStyle(Color.appTitle)
            Text("Elige un curso de la barra lateral para editarlo.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}