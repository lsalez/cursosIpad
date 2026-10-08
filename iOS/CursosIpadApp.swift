// CursosIpadApp.swift
//
// Entry point for the iOS app. Phase 0 ships a placeholder "hello world"
// screen so the project skeleton can build and run before Phase 1 fills
// in the real library UI.

import Shared
import SwiftUI

@main
struct CursosIpadApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

private struct ContentView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("cursosIpad")
                .font(.system(size: 36, weight: .bold, design: .rounded))
            Text("Fase 0 — Andamiaje")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Shared v\(Shared.version)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding()
    }
}
