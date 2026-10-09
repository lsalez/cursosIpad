// MacSettings.swift
//
// User preferences that the macOS app needs to persist between
// launches. Right now there's just one: the library root URL.
//
// We use `UserDefaults.standard` directly rather than `@AppStorage`
// because:
//   * `@AppStorage` works on `RawRepresentable` enums and primitive
//     types but not on `URL`. We'd otherwise need to round-trip
//     through a `String` property anyway, so the explicit accessor
//     is cleaner.
//   * The library root is a `URL` (file:// or file path), and we
//     want to keep the absolute form (not the bookmark form) so
//     the user can move the folder and we re-resolve on launch
//     via `URL.path` checks. That's the same behavior the iOS app
//     has with `Documents/`.
//
// The default (`~/Movies/CursosIpad/`) lives here so a fresh
// `MacLibraryStore()` knows where to look without any user
// configuration.

import Foundation

enum MacSettings {
    /// `UserDefaults` key for the library root. Public so the
    /// `SettingsView` can read it for the "Reset" button without
    /// having to plumb the value through a binding.
    static let libraryURLKey = "macLibraryURL"

    /// Default library root per plan §15.1. We expand the leading
    /// `~` against the user's home directory so the value the
    /// `MacCourseIndexer` actually walks is absolute.
    static func defaultLibraryURL() -> URL {
        let movies = FileManager.default.urls(
            for: .moviesDirectory,
            in: .userDomainMask
        ).first ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Movies", isDirectory: true)
        return movies.appendingPathComponent("CursosIpad", isDirectory: true)
    }

    /// Load the persisted library root, falling back to the default
    /// when no value is stored or the stored value can't be resolved
    /// to a real `URL` (defensive: legacy / corrupt data).
    static func loadLibraryURL() -> URL {
        guard let raw = UserDefaults.standard.string(forKey: libraryURLKey),
              let url = URL(string: raw) else {
            return defaultLibraryURL()
        }
        return url
    }

    /// Persist the library root. No-op for the default value so a
    /// user who picks the default doesn't end up with a `~/...`
    /// path string in `UserDefaults` that may go stale if the user
    /// moves their Movies folder.
    static func saveLibraryURL(_ url: URL) {
        if url == defaultLibraryURL() {
            UserDefaults.standard.removeObject(forKey: libraryURLKey)
        } else {
            UserDefaults.standard.set(url.absoluteString, forKey: libraryURLKey)
        }
    }
}