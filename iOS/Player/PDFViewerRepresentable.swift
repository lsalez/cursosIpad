// PDFViewerRepresentable.swift
//
// Thin `UIViewRepresentable` over `PDFKit.PDFView` (Fase 7). Mirrors
// the architectural shape of `VideoPlayerRepresentable` but adapted
// for PDFKit's view-based API (vs. AVKit's controller-based one).
//
// Key lifecycle notes:
//
//   * **`dismantleUIView`** is the right hook here, NOT
//     `dismantleUIViewController` — `PDFView` is a `UIView`, not a
//     `UIViewController`. The video representable uses the controller
//     variant because it wraps `AVPlayerViewController`. Two
//     different hooks, easy to confuse.
//
//   * **The Coordinator owns the `PDFDocument` and the page-change
//     observer.** Loading the document inside the Coordinator
//     (rather than in `updateUIView` or as `@State` on the parent)
//     keeps the document's lifecycle tied to the representable's
//     identity. A `.id(lesson.id)` swap in the parent tears down
//     the old representable, which tears down the old Coordinator,
//     which releases the old document.
//
//   * **Notification observer registration is the only reason the
//     Coordinator exists as a separate type.** The
//     `PDFViewPageChanged` notification fires on the main thread;
//     removing the observer in `dismantleUIView` is non-negotiable,
//     otherwise lesson swaps leak observers that point at dead
//     Coordinators (and the new Coordinator never sees page-change
//     events for the second PDF).
//
//   * **Resume is synchronous.** `PDFView.go(to:)` is sync — by the
//     time `makeUIView` returns, the page is set. We don't need
//     the two-gate pattern from the video player. We DO subscribe
//     to the notification *after* issuing the initial seek, so the
//     first notification the observer sees is a real user-driven
//     change (not the resume seek itself).
//
//   * **`updateUIView` is a no-op.** The parent's `.id(lesson.id)`
//     guarantees a fresh `makeUIView` per lesson, so there is no
//     "doc changed underneath me" race to handle. If we ever wire
//     an explicit "jump to page N" parent-driven API, it would
//     route through a method on the Coordinator.

import PDFKit
import SwiftUI

// MARK: - Main viewer

struct PDFViewerRepresentable: UIViewRepresentable {

    /// Absolute URL of the PDF document. The parent resolves this
    /// via `LibraryStore.itemURL(for:item:)` before rendering.
    let url: URL

    /// 1-indexed page to seek to on first display. `nil` means
    /// "open at the first page" — `PDFView` defaults to page 1 after
    /// a document assignment, so we don't issue a redundant
    /// `go(to:)` call in that case.
    let initialPage: Int?

    /// Binding back to the parent's `@State` so the sibling
    /// `PDFThumbnailRepresentable` can link to the live `PDFView`
    /// (the thumbnail view needs the main view to handle selection
    /// and to highlight the current page). The parent's `@State`
    /// is the canonical owner of the reference; the representable
    /// just publishes it.
    @Binding var pdfView: PDFView?

    /// Closure invoked on every user-driven page change. The parent
    /// uses this to call `LibraryStore.updateItemProgress` (which
    /// persists via the `SidecarWriter` actor). Called on the main
    /// thread by `NotificationCenter`.
    let onPageChanged: (Int) -> Void

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .systemBackground

        // Load the document. `PDFDocument(url:)` returns `nil` for
        // unreadable / missing files; the parent already filtered
        // for that case via `loadError` in its `.task`, so reaching
        // here with a bad URL is a programmer error we surface as
        // a no-op (no document, no observer, the empty view stays).
        guard let document = PDFDocument(url: url) else {
            context.coordinator.document = nil
            return view
        }
        context.coordinator.document = document
        view.document = document

        // Resume seek. Only if we have a target page > 1 — page 1 is
        // the default after document assignment, no seek needed.
        if let initialPage, initialPage > 1,
           let target = document.page(at: initialPage - 1)
        {
            view.go(to: target)
        }

        // Subscribe to page changes AFTER the initial seek so the
        // observer never sees the resume itself. The `object:`
        // parameter scopes the notification to *this* PDFView
        // instance — without it, every PDFView in the app would
        // notify every observer, and the Coordinator would see
        // events from PDFs it doesn't own.
        let token = NotificationCenter.default.addObserver(
            forName: .PDFViewPageChanged,
            object: view,
            queue: .main
        ) { [onPageChanged] _ in
            // `currentPage` is `nil` between documents; default to
            // page 1 in that pathological case so the writer never
            // crashes on a forced unwrap. The parent already
            // validates that the document is loaded, so this is
            // belt-and-suspenders.
            let pageIndex = view.currentPage?.pageRef?.pageNumber
                ?? (view.document?.index(for: view.currentPage ?? PDFPage()) ?? 0) + 1
            onPageChanged(max(1, pageIndex))
        }
        context.coordinator.observerToken = token

        // Publish the live view to the parent. Deferred to the next
        // runloop tick so the binding write happens after `makeUIView`
        // returns — SwiftUI forbids mutating state from within view
        // builders / `makeUIView`.
        DispatchQueue.main.async { [weak view] in
            self.pdfView = view
        }

        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // No-op. See the file header for the rationale.
    }

    static func dismantleUIView(_ uiView: PDFView, coordinator: Coordinator) {
        // 1. Remove the page-change observer. CRITICAL — without
        //    this, every lesson swap leaks an observer that points
        //    at a Coordinator whose `onPageChanged` closure is
        //    about to be deallocated. Symptom of forgetting this:
        //    "the second PDF I open never updates its lastPage."
        if let token = coordinator.observerToken {
            NotificationCenter.default.removeObserver(token)
        }
        // 2. Detach the document. Frees the PDFDocument (and its
        //    decoded page buffers) immediately rather than waiting
        //    for SwiftUI to drop the view.
        uiView.document = nil
        // 3. Nil out Coordinator fields for hygiene.
        coordinator.observerToken = nil
        coordinator.document = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        // The PDFDocument. Held here so its lifetime is tied to the
        // Coordinator (and therefore to the representable's
        // identity), not to the `UIView` itself. `PDFDocument` is
        // reference-counted; the Coordinator being the sole owner
        // means the document is released the moment
        // `dismantleUIView` runs.
        var document: PDFDocument?

        // The NotificationCenter observer token. The Notification
        // is scoped to the specific `PDFView` (via `object: view`
        // in `addObserver`), so the Coordinator doesn't need to
        // know which view it belongs to — the token alone is enough
        // to remove the observer in `dismantleUIView`.
        var observerToken: NSObjectProtocol?
    }
}

// MARK: - Thumbnail strip / column

/// Sidekick of `PDFViewerRepresentable` — wraps `PDFKit.PDFThumbnailView`
/// and links it to the main `PDFView` (via `pdfView` property). The
/// parent decides when to render this (via `if showThumbnails`) and
/// where (iPad side column, iPhone bottom strip).
///
/// Lifecycle is intentionally separate from the main representable:
/// each is its own `UIViewRepresentable`, and SwiftUI's identity
/// rules mean they mount and tear down together when the parent
/// re-renders. The `parentPDFView` reference is `weak` inside
/// `PDFThumbnailView` (the SDK property, not ours) — that's the
/// SDK's guarantee that we can't create a retain cycle through the
/// thumbnail → main view link.
struct PDFThumbnailRepresentable: UIViewRepresentable {

    let url: URL
    let parentPDFView: PDFView?

    func makeUIView(context: Context) -> PDFThumbnailView {
        let view = PDFThumbnailView()
        view.layoutMode = .vertical
        view.pdfView = parentPDFView
        view.backgroundColor = .secondarySystemBackground
        return view
    }

    func updateUIView(_ uiView: PDFThumbnailView, context: Context) {
        // The parent re-binds `parentPDFView` whenever the main
        // representable's `makeUIView` publishes a new view
        // (i.e., on every lesson swap). Forwarding the assignment
        // here keeps the thumbnail's selection highlight in sync.
        uiView.pdfView = parentPDFView
    }

    static func dismantleUIView(_ uiView: PDFThumbnailView, coordinator: Coordinator) {
        // Drop the link to the main PDFView. SDK property is `weak`,
        // so this is a no-op in terms of retain counts, but it
        // makes the intent explicit and avoids the thumbnail
        // briefly pointing at a view that's mid-tear-down.
        uiView.pdfView = nil
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator {
        // Reserved for future per-thumbnail state (e.g., a custom
        // selection observer). Empty for Fase 7.
    }
}
