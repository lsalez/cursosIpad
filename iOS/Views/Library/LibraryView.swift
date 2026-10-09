// LibraryView.swift
//
// The iOS library screen: search bar, tag chips, sort + display-mode
// toolbar, grid (or list) of course cards, empty state, floating "+"
// menu. The grid is `LazyVGrid` so the catalog scrolls smoothly with
// hundreds of courses.
//
// Source of truth: a `LibraryStore` injected via `@EnvironmentObject`.
// The app-wide store is created in `CursosIpadApp` so this view (and
// the detail view) look at the same `courses` snapshot.
//
// Wrapped in a `NavigationStack` here so iPhone gets the standard
// push/transition behavior. On iPad the host (`RootView`) puts this
// same view inside a `NavigationSplitView` sidebar — that gives us the
// split layout without duplicating any UI code.
//
// **Fase 4 — search:** when `searchText` is non-empty, we swap the
// body for `SearchResultsView`, which shows the three sections
// (Cursos / Subtítulos / HTMLs). The same `.searchable` modifier
// drives both modes; the parent decides what to do with the results
// via callbacks.

import Shared
import SwiftUI

struct LibraryView: View {
    @EnvironmentObject private var store: LibraryStore

    /// Called when the user taps a course card. The parent decides
    /// how to route the selection — push on iPhone (`NavigationStack`
    /// path), update the detail column on iPad
    /// (`NavigationSplitView` selection), etc. We use a closure
    /// rather than `NavigationLink(value:)` because the latter
    /// doesn't update the iPad split-view detail column reliably.
    let onSelectCourse: (Course) -> Void

    /// Called when the user taps a lesson-title search result (the
    /// "Lecciones" section). The parent sets `store.highlightedItem`
    /// so the detail view can scroll to the lesson and routes to
    /// the course the same way as a card tap.
    let onSelectLesson: (LessonHit) -> Void

    /// Called when the user taps a subtitle search result. The
    /// parent is responsible for setting
    /// `store.highlightedItem` / `store.pendingSearchPosition` and
    /// then routing to the course (the same `onSelectCourse` path).
    let onSelectSubtitle: (SubtitleHit) -> Void

    /// Called when the user taps an HTML search result. Same
    /// contract as `onSelectSubtitle`.
    let onSelectHtml: (HtmlHit) -> Void

    @State private var searchText: String = ""
    @State private var selectedTag: String? = nil
    @State private var sortOrder: LibrarySortOrder = .alphabetical
    @State private var displayMode: LibraryDisplayMode = .grid
    @State private var addMenuPresented: Bool = false
    @State private var pendingAlertMessage: String?

    /// True when the user has typed something. Used to swap between
    /// the catalog grid and the search results view.
    private var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if !isSearching && !availableTags.isEmpty {
                    TagChipsRow(
                        tags: availableTags,
                        selected: $selectedTag
                    )
                    .padding(.bottom, 8)
                }
                if store.isIndexing {
                    SearchIndexingBanner(progress: store.indexProgress)
                        .padding(.bottom, 8)
                }
                content
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 96) // breathing room for the FAB
        }
        .background(Color.appBackground.ignoresSafeArea())
        .navigationTitle("Mis cursos")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $searchText, prompt: "Buscar curso, subtítulo o HTML")
        .toolbar { toolbarContent }
        .refreshable { await store.refresh() }
        .task { await store.refresh() }
        .onChange(of: searchText) { _, newValue in
            // Forward every keystroke to the store. The service
            // debounces internally so this doesn't translate into a
            // query per keystroke.
            store.updateSearch(newValue)
        }
        .onSubmit(of: .search) {
            // Force an immediate run of the current query (skips
            // the debounce). Tapping "Search" on the keyboard
            // should feel snappy.
            store.updateSearch(searchText)
        }
        .overlay(alignment: .bottomTrailing) { addMenuButton }
        .confirmationDialog(
            "Agregar curso",
            isPresented: $addMenuPresented,
            titleVisibility: .visible
        ) {
            Button("Recibir por WiFi") {
                notifyNotImplemented(feature: "Recibir por WiFi (Fase 11)")
            }
            Button("Mostrar en Archivos") {
                showDocumentsPath()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Los cursos se guardan en Documentos › cursosIpad dentro de la app Archivos.")
        }
        .alert(
            "Próximamente",
            isPresented: Binding(
                get: { pendingAlertMessage != nil },
                set: { if !$0 { pendingAlertMessage = nil } }
            ),
            presenting: pendingAlertMessage
        ) { _ in
            Button("OK", role: .cancel) { pendingAlertMessage = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Filtered + sorted courses (catalog mode)

    private var visibleCourses: [Course] {
        let bySearch = searchText.isEmpty
            ? store.courses
            : store.courses.filter { $0.title.localizedCaseInsensitiveContains(searchText) }

        let byTag: [Course]
        if let selectedTag {
            byTag = bySearch.filter { $0.tags.contains(selectedTag) }
        } else {
            byTag = bySearch
        }

        return byTag.sorted(by: sortOrder.comparator)
    }

    /// All unique tags across the library, plus `nil` representing
    /// "Todos". Sorted alphabetically with Spanish locale so
    /// accents land where users expect.
    private var availableTags: [String] {
        let all = store.courses.flatMap(\.tags)
        let unique = Array(Set(all))
        return unique.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isSearching {
            searchContent
        } else {
            catalogContent
        }
    }

    @ViewBuilder
    private var searchContent: some View {
        if store.searchResults.isEmpty && !store.isIndexing {
            LibraryNoResultsState(searchText: searchText, selectedTag: nil)
                .padding(.top, 48)
        } else {
            SearchResultsView(
                results: store.searchResults,
                store: store,
                onSelectCourse: onSelectCourse,
                onSelectLesson: onSelectLesson,
                onSelectSubtitle: onSelectSubtitle,
                onSelectHtml: onSelectHtml
            )
        }
    }

    @ViewBuilder
    private var catalogContent: some View {
        if store.isLoading && store.courses.isEmpty {
            ProgressView("Escaneando…")
                .frame(maxWidth: .infinity)
                .padding(.top, 80)
        } else if store.courses.isEmpty {
            LibraryEmptyState()
                .padding(.top, 48)
        } else if visibleCourses.isEmpty {
            LibraryNoResultsState(searchText: searchText, selectedTag: selectedTag)
                .padding(.top, 48)
        } else {
            switch displayMode {
            case .grid:
                CourseGrid(
                    courses: visibleCourses,
                    store: store,
                    onSelectCourse: onSelectCourse
                )
            case .list:
                CourseList(
                    courses: visibleCourses,
                    store: store,
                    onSelectCourse: onSelectCourse
                )
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarTrailing) {
            Menu {
                Picker("Orden", selection: $sortOrder) {
                    ForEach(LibrarySortOrder.allCases) { order in
                        Label(order.title, systemImage: order.iconName).tag(order)
                    }
                }
            } label: {
                Label("Orden", systemImage: "arrow.up.arrow.down")
            }
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                displayMode = (displayMode == .grid) ? .list : .grid
            } label: {
                Label(
                    displayMode == .grid ? "Lista" : "Cuadrícula",
                    systemImage: displayMode == .grid ? "list.bullet" : "square.grid.2x2"
                )
            }
        }
    }

    // MARK: - Add menu

    private var addMenuButton: some View {
        Button {
            addMenuPresented = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Circle().fill(Color.appMenu))
                .shadow(color: .black.opacity(0.18), radius: 6, y: 2)
        }
        .padding(.trailing, 20)
        .padding(.bottom, 24)
        .accessibilityLabel("Agregar curso")
    }

    // MARK: - Placeholder actions

    private func notifyNotImplemented(feature: String) {
        // Trivial alert via local state. Fase 11 will hook this to the
        // real WiFi transfer flow.
        pendingAlertMessage = feature
    }

    private func showDocumentsPath() {
        guard let docs = FileManager.default.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else { return }
        // Courses live directly under `Documents/`; this is the
        // folder exposed in the system Files app under "On My iPad".
        pendingAlertMessage = "Tus cursos viven en:\n\(docs.path)\n\nAgrégalos desde la app Archivos."
    }
}

// MARK: - Sort + display mode

enum LibrarySortOrder: String, CaseIterable, Identifiable {
    case alphabetical
    case recent
    case progress

    var id: String { rawValue }

    var title: String {
        switch self {
        case .alphabetical: return "A–Z"
        case .recent: return "Recientes"
        case .progress: return "% avance"
        }
    }

    var iconName: String {
        switch self {
        case .alphabetical: return "textformat"
        case .recent: return "clock"
        case .progress: return "chart.bar"
        }
    }

    var comparator: (Course, Course) -> Bool {
        switch self {
        case .alphabetical:
            return { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        case .recent:
            return { lhs, rhs in
                let l = lhs.allItems.compactMap(\.progress.lastViewedAt).max() ?? .distantPast
                let r = rhs.allItems.compactMap(\.progress.lastViewedAt).max() ?? .distantPast
                return l > r
            }
        case .progress:
            return { $0.totalProgress > $1.totalProgress }
        }
    }
}

enum LibraryDisplayMode {
    case grid
    case list
}

// MARK: - Grid + list layouts

private struct CourseGrid: View {
    let courses: [Course]
    let store: LibraryStore
    let onSelectCourse: (Course) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 160, maximum: 220), spacing: 12, alignment: .top),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
            ForEach(courses) { course in
                Button {
                    onSelectCourse(course)
                } label: {
                    CourseCardView(course: course, store: store)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct CourseList: View {
    let courses: [Course]
    let store: LibraryStore
    let onSelectCourse: (Course) -> Void

    var body: some View {
        VStack(spacing: 8) {
            ForEach(courses) { course in
                Button {
                    onSelectCourse(course)
                } label: {
                    CourseCardView(course: course, store: store)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Tag chips

private struct TagChipsRow: View {
    let tags: [String]
    @Binding var selected: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Chip(label: "Todos", isOn: selected == nil) {
                    selected = nil
                }
                ForEach(tags, id: \.self) { tag in
                    Chip(label: tag, isOn: selected == tag) {
                        selected = (selected == tag) ? nil : tag
                    }
                }
            }
            .padding(.horizontal, 2)
        }
    }
}

private struct Chip: View {
    let label: String
    let isOn: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule(style: .continuous)
                        .fill(isOn ? Color.appMenu : Color.appMenu.opacity(0.08))
                )
                .foregroundStyle(isOn ? Color.white : Color.appMenu)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - "No results" state (have courses, but search/tag excluded them)

private struct LibraryNoResultsState: View {
    let searchText: String
    let selectedTag: String?

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36))
                .foregroundStyle(Color.appInfo)
            Text("Sin resultados")
                .font(.headline)
                .foregroundStyle(Color.appTitle)
            Text(detail)
                .font(.subheadline)
                .foregroundStyle(Color.appInfo)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var detail: String {
        switch (searchText.isEmpty, selectedTag) {
        case (false, .some(let tag)):
            return "No hay cursos que coincidan con “\(searchText)” en la etiqueta \(tag)."
        case (false, nil):
            return "No hay cursos, subtítulos ni HTMLs que coincidan con “\(searchText)”."
        case (true, .some(let tag)):
            return "No tienes cursos con la etiqueta \(tag) todavía."
        case (true, nil):
            return ""
        }
    }
}
