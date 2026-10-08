// HTMLViewerRepresentable.swift
//
// Thin `UIViewRepresentable` over `WKWebView` (Fase 8). Mirrors the
// architectural shape of `PDFViewerRepresentable` and
// `VideoPlayerRepresentable` — a Coordinator owns state tied to the
// representable's identity, so a `.id(item.id)` swap in the parent
// tears down the old WebView cleanly.
//
// Key lifecycle notes:
//
//   * **`dismantleUIView`** is the right hook for `WKWebView` (it's a
//     `UIView`, not a `UIViewController`). Same as `PDFViewer`.
//
//   * **Loading local files with relative-link access.** We use
//     `loadFileURL(_:allowingReadAccessTo: courseDir)` so any relative
//     link (e.g. `<a href="intro.html">`) resolves against the course
//     directory and the click navigates to the linked file in place.
//     `decidePolicyFor` blocks anything that isn't a `file://` URL
//     inside the granted directory — no network access for course
//     HTML, ever.
//
//   * **Resume is a two-step restore.** `WKWebView` resets
//     `scrollView.contentOffset` to zero on every load, so we restore
//     the saved position in `webView(_:didFinish:)` (DOM is laid out
//     by then; setting `contentOffset` works without a JS hop).
//
//   * **Search-result paragraph jump.** For HTML search hits (Fase 4)
//     the indexer produces a 1-based paragraph index. We approximate
//     that index by counting block-level elements (`p, h*, li,
//     blockquote, pre, div, section, article, header, footer, main,
//     aside`) in JS and calling `scrollIntoView` on the Nth. The
//     match isn't perfect (the indexer counts blank-line runs in the
//     preprocessed text; we count DOM elements), but it lands close
//     enough for MVP and is robust to missing tags.
//
//   * **Scroll position persistence.** Saved on `dismantleUIView`
//     (the "on close" hook the plan calls out), on
//     `webView(_:didFinish:)` (so a user who lands on a different
//     page via relative link still gets the new page's position
//     saved), and on the parent's `onDismiss`. The value passed to
//     the parent is the y-offset in **virtual seconds** (offset.y /
//     100) — see plan §17. The factor isn't load-bearing; we just
//     round-trip on resume.

import SwiftUI
import UIKit
import WebKit

// MARK: - Main viewer

struct HTMLViewerRepresentable: UIViewRepresentable {

    /// Absolute URL of the HTML document. The parent resolves this
    /// via `LibraryStore.itemURL(for:item:)`.
    let url: URL

    /// Course directory that hosts the HTML file. Granted to the
    /// web view so relative links resolve and the linked file
    /// (a sibling `.html`, a referenced `.pdf`, etc.) loads. Same
    /// shape as `loadFileURL(_:allowingReadAccessTo:)`.
    let allowingReadAccessTo: URL

    /// Y-offset (in **virtual seconds** — offset.y / 100) to restore
    /// after the page finishes loading. `nil` means "start at the
    /// top".
    let initialPositionSeconds: Double?

    /// 1-based paragraph index to scroll to once the page has
    /// finished loading. The block-element list is approximate; see
    /// the file header.
    let initialParagraphIndex: Int?

    /// Closure invoked whenever the user-driven scroll position
    /// settles on a new value, and on `dismantleUIView`. Called on
    /// the main thread (the UIScrollView delegate runs on main, and
    /// `dismantleUIView` runs on the main actor). The parent uses
    /// this to call `LibraryStore.updateItemProgress` via the
    /// `SidecarWriter` actor (Fase 5).
    let onScrollChanged: (Double) -> Void

    /// Fires exactly once after the resume seek (or paragraph jump)
    /// is issued. The parent uses this to clear its local
    /// `pendingPosition` and the store-level intent. Same shape as
    /// `VideoPlayerView.onPositionConsumed`.
    let onPositionConsumed: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        // We don't need JS-to-native bridges for MVP — the only JS we
        // run is `scrollIntoView`, which is purely client-side.
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.backgroundColor = .systemBackground
        // Disable scroll-view content insets so the HTML fills the
        // view edge-to-edge. The top-bar chrome sits above the view,
        // so we don't need the system to leave room for a nav bar.
        webView.scrollView.contentInsetAdjustmentBehavior = .never

        // Register the scroll observer for "user is scrolling"
        // position writes. `WKWebView` is a `UIScrollView`, but the
        // `UIScrollViewDelegate` methods aren't called for a plain
        // `WKWebView` — Apple's contract puts the delegate
        // responsibilities on `WKNavigationDelegate` for navigation
        // and a separate KVO/subscriber for scroll. KVO on
        // `scrollView.contentOffset` is the simplest path here.
        let scrollObservation = webView.scrollView.observe(
            \.contentOffset,
            options: [.new]
        ) { scrollView, _ in
            let offset = Self.offset(from: scrollView.contentOffset.y)
            // Don't persist a position that's already in flight from
            // the initial seek — the resume-race gate from the video
            // player. We track this with a flag on the coordinator
            // that the navigation delegate flips off once the
            // initial restore has fired.
            let coordinator = context.coordinator
            if coordinator.hasIssuedInitialRestore {
                coordinator.pendingOffset = offset
            }
        }
        context.coordinator.scrollObservation = scrollObservation
        context.coordinator.webView = webView
        context.coordinator.allowedRoot = allowingReadAccessTo.standardizedFileURL.path
        context.coordinator.url = url
        context.coordinator.initialPositionSeconds = initialPositionSeconds
        context.coordinator.initialParagraphIndex = initialParagraphIndex
        context.coordinator.onScrollChanged = onScrollChanged
        context.coordinator.onPositionConsumed = onPositionConsumed

        // Issue the initial load. The delegate's `didFinish` restores
        // the scroll position (or jumps to the paragraph) and flips
        // the gate.
        webView.loadFileURL(url, allowingReadAccessTo: allowingReadAccessTo)

        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No-op. The parent's `.id(item.id)` guarantees a fresh
        // `makeUIView` per lesson, so there is no "doc changed
        // underneath me" race to handle.
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        // 1. Final flush of the scroll position. Two writes happen
        //    back-to-back on the parent's `onScrollChanged` closure;
        //    the `SidecarWriter` actor (Fase 5) serializes them.
        if coordinator.hasIssuedInitialRestore, let pending = coordinator.pendingOffset {
            coordinator.onScrollChanged(pending)
        }
        // 2. Invalidate the KVO observer. CRITICAL — without this,
        //    every lesson swap leaks an observer on a dead
        //    Coordinator's webView. The observer holds the WKWebView
        //    strongly through KVO's mechanism, so we'd otherwise
        //    pin the old view in memory until the next swap.
        coordinator.scrollObservation?.invalidate()
        coordinator.scrollObservation = nil
        // 3. Drop the navigation delegate. Stops the WebView from
        //    calling back into a soon-to-be-deallocated Coordinator.
        uiView.navigationDelegate = nil
        // 4. Stop any in-flight load. Without this, a slow page that
        //    finishes loading after dismantle would invoke the
        //    delegate on a released Coordinator.
        uiView.stopLoading()
        // 5. Drop the WKWebView reference.
        coordinator.webView = nil
    }

    // MARK: - Helpers

    /// Convert a y-offset to "virtual seconds". 1s = 100 px is the
    /// heuristic from plan §17 — close to one line of default-font
    /// text, so the stored value roughly tracks "minutes spent
    /// reading" for analytics later. The factor is non-load-bearing
    /// (we only round-trip it), but we keep the math in one place so
    /// any future tuning happens here.
    static func offset(from yOffset: Double) -> Double {
        max(0, yOffset / 100.0)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, WKNavigationDelegate {

        // The WKWebView we own. Tied to the Coordinator's lifetime,
        // which is tied to the representable's identity (via SwiftUI's
        // `.id(item.id)` contract on the parent).
        weak var webView: WKWebView?

        // Initial-load parameters. Captured in `makeUIView` so the
        // delegate can read them when `didFinish` fires.
        var url: URL?
        var allowedRoot: String = ""
        var initialPositionSeconds: Double?
        var initialParagraphIndex: Int?
        var onScrollChanged: (Double) -> Void = { _ in }
        var onPositionConsumed: () -> Void = {}

        // KVO token for `scrollView.contentOffset`. Held strongly;
        // invalidated in `dismantleUIView`.
        var scrollObservation: NSKeyValueObservation?

        // The most recent scroll offset (virtual seconds) seen while
        // the gate is open. Flushed on dismantle.
        var pendingOffset: Double?

        // Resume-race gate. Until the initial restore (or paragraph
        // jump) fires, we don't persist scroll observations — they
        // come from the layout settling around the resume, not from
        // the user. Same shape as the video player's two-gate
        // pattern; collapsed to one flag here because HTML is
        // synchronous (no AVPlayer-style "didReceiveFirstContentTime"
        // to wait for).
        var hasIssuedInitialRestore: Bool = false

        // Did the dismissal fire the onPositionConsumed callback?
        // Gated so a `.id(item.id)` swap can't double-fire it.
        var didCallOnPositionConsumed: Bool = false

        // MARK: WKNavigationDelegate

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            // Allow the initial load (`navigationAction.navigationType
            // == .other` and `request.url == url`).
            // Allow any file:// URL that's inside the granted
            // directory (relative links work). Block anything else
            // (network, `about:blank` reloads from JS, mailto, etc.).
            guard let target = navigationAction.request.url else {
                decisionHandler(.cancel)
                return
            }
            if target.isFileURL {
                let standardized = target.standardizedFileURL.path
                if standardized.hasPrefix(allowedRoot) {
                    decisionHandler(.allow)
                    return
                }
                // Some file:// URLs (e.g. anchor links like
                // `file:///path/index.html#section`) live inside the
                // grant but have a different scheme fragment. The
                // `hasPrefix` check above covers them via path
                // equality.
                decisionHandler(.cancel)
                return
            }
            // Non-file URLs (http/https/data/etc.): block. Course
            // HTML is sandboxed.
            decisionHandler(.cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Resume path. Restoring `contentOffset` directly works
            // here because the DOM is laid out by `didFinish` and the
            // scroll view already knows the content size.
            if let initial = initialPositionSeconds, initial > 0 {
                let targetY = CGFloat(initial * 100.0)
                let clampedY = min(
                    targetY,
                    max(0, webView.scrollView.contentSize.height - webView.scrollView.bounds.height)
                )
                webView.scrollView.setContentOffset(
                    CGPoint(x: 0, y: clampedY),
                    animated: false
                )
            } else if let paragraph = initialParagraphIndex, paragraph > 0 {
                // Search-result jump. Use JS to find the Nth block
                // element and scroll it into view. Done synchronously
                // (no completion handler) because we don't need the
                // return value and `scrollIntoView` returns void.
                let js = Self.scrollToParagraphJS(paragraph)
                webView.evaluateJavaScript(js, completionHandler: nil)
            }

            hasIssuedInitialRestore = true

            // Fire the consumed callback exactly once per lesson.
            if !didCallOnPositionConsumed,
               (initialPositionSeconds ?? 0) > 0 || (initialParagraphIndex ?? 0) > 0
            {
                didCallOnPositionConsumed = true
                onPositionConsumed()
            }
        }

        func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            // Failures during navigation (network unreachable, etc.)
            // — surface to the console; the parent's error chrome
            // (file not found) covers the "this HTML is missing"
            // case. We still open the gate so subsequent scroll
            // observations persist.
            print("[HTMLViewer] navigation failed: \(error)")
            hasIssuedInitialRestore = true
        }

        func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            print("[HTMLViewer] provisional navigation failed: \(error)")
            hasIssuedInitialRestore = true
        }

        // MARK: - JS helpers

        /// Scroll the Nth block-level element into view. The selector
        /// mirrors `HtmlIndexer.preprocessHTML`'s closing-tag list so
        /// the DOM index and the text index align as closely as
        /// possible. `1`-based — matches `SearchPosition.html(paragraphIndex:)`.
        static func scrollToParagraphJS(_ paragraphIndex: Int) -> String {
            let selector = "'p,h1,h2,h3,h4,h5,h6,li,blockquote,pre,div,section,article,header,footer,main,aside'"
            let n = paragraphIndex - 1
            return """
            (function() {
                var els = document.querySelectorAll(\(selector));
                if (els.length === 0) return;
                var target = els[\(n)] || els[els.length - 1];
                if (target && target.scrollIntoView) {
                    target.scrollIntoView({ behavior: 'auto', block: 'start' });
                }
            })();
            """
        }
    }
}