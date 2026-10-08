// CourseDescriptionView.swift
//
// Tab "Descripción" — renders the course's description in markdown
// (basic), or a "Sin descripción." placeholder if the sidecar
// doesn't carry one.
//
// In Fase 3 the sidecar doesn't exist yet (it ships in Fase 5), so
// the description is always empty in practice and this view always
// shows the empty state. The rendering pipeline is in place so when
// `Course` grows a `description` (or the parent passes it in) the
// markdown kicks in without further changes.

import SwiftUI

struct CourseDescriptionView: View {
    let description: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let text = description, !text.isEmpty {
                Text(LocalizedStringKey(text))
                    .font(.system(size: 15))
                    .foregroundStyle(Color.appTitle)
                    .textSelection(.enabled)
            } else {
                emptyState
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.appInfo)
            Text("Sin descripción.")
                .font(.headline)
                .foregroundStyle(Color.appTitle)
            Text("Este curso todavía no tiene una descripción.")
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 32)
    }
}
