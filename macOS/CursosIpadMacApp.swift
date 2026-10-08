// CursosIpadMacApp.swift
//
// Entry point for the macOS companion app. Phase 0 ships a placeholder
// "hello world" window so the project skeleton can build and run before
// Phase 9 fills in the real Mac library and editor.

import Shared
import SwiftUI

@main
struct CursosIpadMacApp: App {
    var body: some Scene {
        WindowGroup("cursosIpad") {
            ContentView()
        }
        .windowResizability(.contentSize)
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("cursosIpad")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Fase 0 — Andamiaje (Mac)")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Shared v\(Shared.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(40)
    }
}
