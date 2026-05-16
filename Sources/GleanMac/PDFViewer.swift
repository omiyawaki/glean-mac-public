import SwiftUI
import PDFKit
import AppKit

/// PDFKit's PDFView wrapped for SwiftUI. Single-page-continuous, autoscales
/// to width — matches Preview.app's default reading layout. The view diffs
/// the document URL on update so swapping rows doesn't tear down the view.
///
/// `darkMode` flips pages to a light-on-dark rendering by drawing each page
/// through an `InvertedPDFPage` subclass that overlays a `CGBlendMode.difference`
/// white fill — equivalent to Preview's "Invert Colors" accessibility mode.
/// This inverts everything on the page including embedded photos; selective
/// per-image inversion would require walking each page's content stream with
/// `CGPDFScanner` to recover image XObject rects.
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

        nsView.backgroundColor = darkMode
            ? NSColor(white: 0.12, alpha: 1.0)
            : .clear
    }

    final class Coordinator: NSObject, PDFDocumentDelegate {
        var darkMode = false

        func classForPage() -> AnyClass {
            darkMode ? InvertedPDFPage.self : PDFPage.self
        }
    }
}

/// Renders the page normally, then composites a white fill with
/// `CGBlendMode.difference` over the page bounds. `dest = |white - dest|`
/// is a per-pixel color invert, which gives the same result as Preview's
/// invert-colors mode but baked into the draw call — so the inversion
/// follows zoom, print/export, and PDFKit's tiling without extra layer
/// plumbing.
final class InvertedPDFPage: PDFPage {
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        context.saveGState()
        context.setBlendMode(.difference)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds(for: box))
        context.restoreGState()
    }
}
