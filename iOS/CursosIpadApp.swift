// CursosIpadApp.swift
//
// Entry point for the iOS app. Phase 0 shipped a placeholder "hello
// world" ContentView. Phase 1 swaps that for `DebugLibraryView`,
// which lists courses from `Documents/Cursos/` via `CourseIndexer`.

import SwiftUI

@main
struct CursosIpadApp: App {
    var body: some Scene {
        WindowGroup {
            DebugLibraryView()
        }
    }
}
