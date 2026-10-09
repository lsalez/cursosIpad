// CoverImageLoader.swift
//
// Loads course cover images on demand, with an in-memory cache. The
// covers live inside the course folder
// (`Documents/<name>/cover.jpg`), so the cache is keyed by the
// absolute file URL — that survives re-scans of the courses directory
// without us having to invalidate by course id.
//
// Cache eviction: bounded by `countLimit` and `totalCostLimit` on
// `NSCache`, so a long session with hundreds of covers doesn't grow
// unbounded. The covers are small (a few hundred KB at most) and
// reloading from disk is cheap, so we don't bother with disk caching
// here — Fase 6's `ThumbnailGenerator` will own the on-disk cache for
// video frames; covers come from the user.

import Foundation
import SwiftUI
import UIKit

@MainActor
final class CoverImageLoader: ObservableObject {
    static let shared = CoverImageLoader()

    @Published private(set) var image: UIImage?

    private let url: URL?
    private let cache: NSCache<NSURL, UIImage>

    private init() {
        self.url = nil
        self.cache = NSCache()
        configureCache()
    }

    /// Designated initializer for an instance bound to a single cover
    /// URL. The loader is a `View` model so each course card owns one.
    init(url: URL?) {
        self.url = url
        self.cache = SharedCoverImageCache.shared.cache
        configureCache()
        loadIfNeeded()
    }

    private func configureCache() {
        cache.countLimit = 64
        cache.totalCostLimit = 32 * 1024 * 1024 // 32 MB across all covers
    }

    private func loadIfNeeded() {
        guard let url else {
            image = nil
            return
        }
        if let cached = cache.object(forKey: url as NSURL) {
            image = cached
            return
        }
        Task.detached(priority: .userInitiated) { [url, cache] in
            guard let loaded = UIImage(contentsOfFile: url.path) else { return }
            let cost = Cost.estimate(for: loaded)
            cache.setObject(loaded, forKey: url as NSURL, cost: cost)
            await MainActor.run {
                self.image = loaded
            }
        }
    }
}

private enum SharedCoverImageCache {
    static let shared = Holder()
    final class Holder {
        let cache = NSCache<NSURL, UIImage>()
    }
}

private enum Cost {
    /// Rough cost estimate for NSCache: 4 bytes per pixel plus the CGImage
    /// header. Good enough to keep the cache from blowing up.
    static func estimate(for image: UIImage) -> Int {
        let pixelCount = Int(image.size.width * image.scale * image.size.height * image.scale)
        return pixelCount * 4 + 1024
    }
}
