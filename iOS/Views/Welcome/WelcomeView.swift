// WelcomeView.swift
//
// First-launch screen per plan §14.3. The user sees:
//
//   * A small hero illustration (stack of book/library SF symbols
//     over a soft accent background — no bundled image assets).
//   * A bold title and a one-line subtitle.
//   * A primary "Listo, ya tengo mis cursos" button that sets
//     `hasSeenWelcome` to true and dismisses the screen.
//   * A secondary link "¿Cómo copio mis cursos?" that opens a sheet
//     with the 3-step tutorial from the spec.
//
// The view is hosted by `CursosIpadApp` and only shown when
// `@AppStorage("hasSeenWelcome")` is false. After the user taps
// "Listo" the flag is set and the app moves on to `RootView`.

import SwiftUI

struct WelcomeView: View {
    @AppStorage("hasSeenWelcome") private var hasSeenWelcome: Bool = false
    @State private var tutorialPresented: Bool = false

    var body: some View {
        ZStack {
            backgroundGradient.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    hero
                    Spacer(minLength: 12)
                    VStack(spacing: 10) {
                        Text("Tus cursos, donde vayas.")
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(Color.appTitle)
                            .multilineTextAlignment(.center)
                        Text("Copia desde tu Mac y retoma donde quedaste.")
                            .font(.system(size: 16))
                            .foregroundStyle(Color.appInfo)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    Spacer(minLength: 16)
                    VStack(spacing: 8) {
                        Button {
                            hasSeenWelcome = true
                        } label: {
                            Text("Listo, ya tengo mis cursos")
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color.appMenu)
                                )
                        }
                        .buttonStyle(.plain)

                        Button {
                            tutorialPresented = true
                        } label: {
                            Text("¿Cómo copio mis cursos?")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(Color.appMenu)
                                .padding(.vertical, 8)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
                .padding(.top, 40)
            }
        }
        .sheet(isPresented: $tutorialPresented) {
            WelcomeTutorialSheet(isPresented: $tutorialPresented)
        }
    }

    // MARK: - Hero

    private var hero: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.appMenu)
                .frame(maxWidth: .infinity)
                .frame(height: 220)
            VStack(spacing: 8) {
                Image(systemName: "books.vertical.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundStyle(.white.opacity(0.95))
                Image(systemName: "ipad.landscape")
                    .font(.system(size: 40, weight: .light))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(.horizontal, 24)
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [Color.appBackground, Color.appBackground],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

// MARK: - Tutorial sheet

private struct WelcomeTutorialSheet: View {
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                        stepRow(number: index + 1, step: step)
                    }
                }
                .padding(20)
            }
            .background(Color.appBackground.ignoresSafeArea())
            .navigationTitle("Cómo copiar tus cursos")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cerrar") { isPresented = false }
                }
            }
        }
    }

    private func stepRow(number: Int, step: Step) -> some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color.appMenu)
                    .frame(width: 32, height: 32)
                Text("\(number)")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(step.title)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.appTitle)
                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundStyle(Color.appInfo)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private struct Step {
        let title: String
        let body: String
    }

    private var steps: [Step] {
        [
            Step(
                title: "Prepara una carpeta en tu Mac",
                body: """
                Crea una carpeta con el nombre del curso. Dentro, pon los \
                videos, PDFs y HTMLs en subcarpetas (módulos). Opcional: \
                agrega una portada llamada cover.jpg.
                """
            ),
            Step(
                title: "Conecta por WiFi o USB",
                body: """
                WiFi: en la app Mac, toca "Enviar al iPad" y elige tu \
                dispositivo. USB: arrastra la carpeta a tu iPad en \
                Finder, dentro de Archivos › cursosIpad.
                """
            ),
            Step(
                title: "Listo",
                body: """
                La app iOS detecta el curso al abrirla. Toca una lección \
                para empezar; tu progreso se guarda automáticamente.
                """
            ),
        ]
    }
}
