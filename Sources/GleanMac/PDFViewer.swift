import SwiftUI
import PDFKit
import AppKit

/// PDFKit's PDFView wrapped for SwiftUI. Single-page-continuous, autoscales
/// to width — matches Preview.app's default reading layout. The view diffs
/// the document URL on update so swapping rows doesn't tear down the view.
///
/// `darkMode` flips pages to a light-on-dark rendering by drawing each page
/// through an `InvertedPDFPage` subclass that overlays a `CGBlendMode.difference`
/// fill tuned to a soft-dark color rather than pure white. Pure-white fill is
/// Preview's "Invert Colors" accessibility mode and yields stark `#000000`
/// page backgrounds and `#ffffff` text; the softened fill maps white pages
/// to ~`#181818` (matching Glean's WebViewer Dark Reader theme and macOS
/// native dark window backgrounds) and black text to ~`#e7e7e7`. Everything
/// on the page is still inverted, including embedded photos; selective
/// per-image inversion would require walking each page's content stream
/// with `CGPDFScanner` to recover image XObject rects.
struct PDFViewer: NSViewRepresentable {
    let url: URL?
    var darkMode: Bool = false

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        let coord = context.coordinator
        let urlChanged = nsView.document?.documentURL != url
        let modeChanged = coord.darkMode != darkMode
        coord.darkMode = darkMode

        if urlChanged || modeChanged {
            let savedDest = nsView.currentDestination
            if let url {
                let doc = PDFDocument(url: url)
                doc?.delegate = coord
                nsView.document = doc
            } else {
                nsView.document = nil
            }
            // Restore scroll position when the only thing that changed is
            // dark mode — without this the toggle jumps back to page 1.
            if modeChanged, !urlChanged, let dest = savedDest {
                nsView.go(to: dest)
            }
        }

        // Match the page-background color the .difference fill produces
        // (see InvertedPDFPage.softDarkLevel) so the gutter around pages
        // visually merges with the inverted page background instead of
        // forming a visible seam.
        nsView.backgroundColor = darkMode
            ? NSColor(white: 1.0 - InvertedPDFPage.softDarkLevel, alpha: 1.0)
            : .clear
    }

    final class Coordinator: NSObject, PDFDocumentDelegate {
        var darkMode = false

        func classForPage() -> AnyClass {
            darkMode ? InvertedPDFPage.self : PDFPage.self
        }
    }
}

/// Renders the page normally, then composites a soft-dark fill with
/// `CGBlendMode.difference` over the page bounds. `dest = |fill - dest|`
/// is a per-pixel color invert; choosing the fill brightness controls the
/// extremes of the inverted output. With `fill = (1 - softDarkLevel)`:
///   white page  -> `(1 - fill) = softDarkLevel`   ≈ `#181818`
///   black text  -> `fill        = 1 - softDarkLevel` ≈ `#e7e7e7`
/// matching Glean's WebViewer Dark Reader theme and macOS native dark
/// window backgrounds rather than the stark `#000000`/`#ffffff` extremes
/// of a pure-white-fill inversion. Baking this into `draw(with:to:)` (vs.
/// a layer filter) means the inversion follows zoom, print/export, and
/// PDFKit's tiling without extra layer plumbing.
final class InvertedPDFPage: PDFPage {
    /// Target page-background gray after inversion. 0.094 ≈ `#181818`,
    /// matching `WebViewer.installDarkReader`'s prelude background.
    static let softDarkLevel: CGFloat = 0.094

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        context.saveGState()
        context.setBlendMode(.difference)
        let fillLevel = 1.0 - Self.softDarkLevel
        context.setFillColor(
            NSColor(white: fillLevel, alpha: 1.0).cgColor
        )
        context.fill(bounds(for: box))
        context.restoreGState()
    }
}
