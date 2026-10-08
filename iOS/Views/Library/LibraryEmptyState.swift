// LibraryEmptyState.swift
//
// Shown by `LibraryView` when the courses directory is empty (no
// folders at all). Renders plan §14.4's empty copy in Spanish, with a
// short pointer to the app's Documents directory inside the Files app
// so first-time users can find it.

import SwiftUI

struct LibraryEmptyState: View {
    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "books.vertical")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Aún no tienes cursos")
                .font(.title3.bold())
                .foregroundStyle(Color.appTitle)
                .multilineTextAlignment(.center)
            Text("Agrega una carpeta de curso desde tu Mac (por WiFi o USB). La app la detectará al reabrir.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 16)
        }
        .frame(maxWidth: .infinity)
    }
}
