// CursosIpadApp.swift
//
// Entry point for the iOS app. Phase 0 shipped a placeholder; Phase 1
// mounted `DebugLibraryView`; Phase 2 replaces that with the real
// library, hosted behind a `RootView` that adapts to the device:
//
//   - iPhone / compact width: single `NavigationStack` so the library
//     is the root and selecting a course pushes the detail.
//   - iPad / regular width: `NavigationSplitView` with the library on
//     the left and a detail placeholder on the right. The placeholder
//     sticks around until Fase 3 wires the real course detail view.
//
// The `LibraryStore` is created once at the app scope and injected
// via `@EnvironmentObject` so every view (library, detail, future
// search) sees the same `courses` snapshot.

import SwiftUI

@main
struct CursosIpadApp: App {
    @StateObject private var library = LibraryStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(library)
        }
    }
}

/// Top-level container. Decides between a single `NavigationStack`
/// and a `NavigationSplitView` based on the current horizontal size
/// class. The library view itself is identical in both cases — the
/// split view is just chrome.
struct RootView: View {
    @Environment(\.horizontalSizeClass) private var horizontalSize

    var body: some View {
        if horizontalSize == .regular {
            NavigationSplitView {
                NavigationStack {
                    LibraryView()
                }
            } detail: {
                NavigationStack {
                    CourseSelectionPlaceholder()
                }
            }
            .navigationSplitViewStyle(.balanced)
        } else {
            NavigationStack {
                LibraryView()
            }
        }
    }
}

/// Detail-column placeholder shown on iPad until the user picks a
/// course. Replaced by `CourseDetailView` in Fase 3.
private struct CourseSelectionPlaceholder: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Selecciona un curso")
                .font(.title3.bold())
                .foregroundStyle(Color.appTitle)
            Text("Toca un curso de la biblioteca para ver su contenido.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.appBackground.ignoresSafeArea())
    }
}
