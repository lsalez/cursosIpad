# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Source of truth: `plan.md`

**All design, architecture, scope, phases, and risks live in [`plan.md`](./plan.md).** Read it before doing any work — do not duplicate its content here, point to the relevant section instead.

`plan.md` has these top-level sections:

| § | Topic |
|---|-------|
| 1–3 | Visión, decisiones de producto, casos de uso |
| 4–5 | Alcance MVP y fuera de alcance |
| 6–8 | Arquitectura, stack, estructura del proyecto |
| 9–12 | Estructura en disco, protocolo WiFi, modelos, sidecar JSON |
| 13 | Miniaturas (thumbnails de video) |
| 14–15 | UI iOS / Mac (incluye paleta SPID en §14.1.1) |
| 16–17 | Búsqueda full-text, progreso |
| 18 | Plan de implementación por fases (14 fases con checklist) |
| 19 | Riesgos y decisiones pendientes |

The `## Progreso` block at the top of `plan.md` shows the current phase.

## Workflow: review-then-commit

The user wants to review every change before it is committed. The default loop is:

1. Make the change.
2. Tell the user what changed (files touched, summary, decisions taken).
3. **Stop and wait.** Do NOT run `git add` / `git commit` until the user explicitly says so.
4. When the user says "commit" / "commitea" / "go ahead":
   - Stage specific files (not `git add .` unless told otherwise).
   - Commit with a Conventional Commits message in English, subject ≤ 72 chars, imperative mood.
   - Author is the git config user (`Mac M3 <git@salez.mx>` on this machine).
   - **Do NOT** add `Co-Authored-By: Claude Code` or any "🤖 Generated with" footer.
5. After committing, show the resulting commit hash.

If a change is large or ambiguous, propose the diff and wait for approval before applying.

## Implementation phases

Work is tracked in 14 phases in `plan.md` §18. Each phase has a granular checklist of `- [ ]` items. **Claude closes a phase** by updating the `## Progreso` block at the top of `plan.md` (full rule in the `## Progreso` section itself).

When working on a phase:

- Read the phase's checklist before starting — don't skip items.
- Add new checks to the current phase if scope grows; don't silently expand it.
- The phase's **Entregable** describes what must work before moving on.
- Don't start a new phase until the current one's checklist is 100% green and the Entregable is met.

The Fase 0 (Andamiaje) creates the Xcode project and is the first concrete work; nothing before it produces code.

## Stack (summary)

- **iOS:** Swift 5.9+, SwiftUI iOS 17+, AVKit / PDFKit / WKWebView.
- **macOS:** SwiftUI macOS 14+, `Network.framework` (Bonjour + `NWListener` / `NWBrowser`).
- **Distribution:** sideload with Xcode. No App Store, no TestFlight.
- **Persistence:** sidecar JSON per course + SQLite FTS5 (built-in) for full-text search.
- **Transfer (WiFi):** HTTP server on iOS, ZIP with `ZIPFoundation` (both ⚠️ por decidir in §19).

Full justification and decisions in `plan.md` §7. Open trade-offs in §19.

## Repo layout (target for end of Fase 0)

```
cursosIpad/                          ← monorepo root
├── README.md                         ← Spanish, user-facing
├── plan.md                           ← Spanish, design + phases
├── CLAUDE.md                         ← this file
├── .gitignore                        ← Xcode, SwiftPM, macOS, editors
└── CursosIpad.xcodeproj             ← to be created in Fase 0
    ├── iOS/                          ← target iOS app
    ├── macOS/                        ← target macOS companion
    └── Shared/                       ← local Swift Package: models, sidecar, transfer protocol
```

`Shared/` is a local Swift Package (not a remote dependency). Both app targets import it. Models like `Course`, `CourseItem`, `ItemProgress` and the `.cursosIpad.json` Codable live there so the contract is defined once.

## What to ask vs. assume

- If the user has already answered the question in `plan.md`, follow that — don't re-ask.
- If something is unclear, ask one question with 2–4 concrete options (`AskUserQuestion`).
- Don't ask multiple questions when one will do.
- Don't introduce new dependencies or libraries without surfacing it.
- Decisions marked `⚠️ por decidir` in `plan.md` §19 can be resolved during the phase that needs them; document the resolution in the plan.