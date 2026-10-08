// Shared.swift
//
// Placeholder module for the local Swift Package shared between the iOS
// and macOS app targets. Concrete types (Course / Module / CourseItem /
// ItemProgress, the sidecar Codable, and the transfer protocol) land in
// subsequent phases per plan.md §18.

import Foundation

public enum Shared {
    /// Current package version. Bumped manually per release.
    public static let version = "0.0.1"
}
