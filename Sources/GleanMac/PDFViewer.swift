import SwiftUI
import PDFKit
import AppKit

struct PDFThumbnailSidebarConfiguration: Equatable {
    var defaultWidth: CGFloat
    var minimumWidth: CGFloat
    var maximumWidth: CGFloat
    var thumbnailSize: CGSize

    static let previewLike = PDFThumbnailSidebarConfiguration(
        defaultWidth: 160,
        minimumWidth: 120,
        maximumWidth: 260,
        thumbnailSize: CGSize(width: 96, height: 128)
    )
}

/// PDFKit's PDFView wrapped for SwiftUI. Single-page-continuous, autoscales
/// to width — matches Preview.app's default reading layout. The view diffs
/// the document URL on update so swapping rows doesn't tear down the view.
///
/// `darkMode` flips pages to a light-on-dark rendering by drawing each page
/// through an `InvertedPDFPage` subclass that overlays a `CGBlendMode.difference`
/// fill tuned to a soft-dark color rather than pure white. Pure-white fill is
/// Preview's "Invert Colors" accessibility mode and yields stark `#000000`
/// page backgrounds and `#ffffff` text; the softened fill maps white pages
/// to ~`#1e1e1e` (matching native macOS dark document backgrounds) and black
/// text to ~`#e1e1e1`. Everything
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

        // Match the page-background color the .difference fill produces so
        // the gutter around pages visually shares the same native dark surface.
        nsView.backgroundColor = darkMode
            ? PDFDarkModePalette.pageBackgroundColor
            : .clear
    }

    final class Coordinator: NSObject, PDFDocumentDelegate {
        var darkMode = false

        func classForPage() -> AnyClass {
            darkMode ? InvertedPDFPage.self : PDFPage.self
        }
    }
}

/// Seeds the page with a white paper fill, renders the page normally, then
/// composites a soft-dark fill with `CGBlendMode.difference` over the page
/// bounds. The white seed matters because many publisher PDFs leave the page
/// background implicit instead of drawing a white rectangle. `dest = |fill -
/// dest|` is a per-pixel color invert; choosing the fill brightness controls
/// the extremes of the inverted output. With `fill = (1 - softDarkLevel)`:
///   white page  -> `(1 - fill) = softDarkLevel`   ≈ `#1e1e1e`
///   black text  -> `fill        = 1 - softDarkLevel` ≈ `#e1e1e1`
/// matching native macOS dark document backgrounds rather than the stark
/// `#000000`/`#ffffff` extremes
/// of a pure-white-fill inversion. Baking this into `draw(with:to:)` (vs.
/// a layer filter) means the inversion follows zoom, print/export, and
/// PDFKit's tiling without extra layer plumbing.
final class InvertedPDFPage: PDFPage {
    /// Target page-background gray after inversion, matching the resolved
    /// macOS dark document background on this SDK.
    static var softDarkLevel: CGFloat {
        PDFDarkModePalette.pageBackgroundLevel
    }

    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        context.saveGState()
        context.setFillColor(NSColor.white.cgColor)
        context.fill(bounds(for: box))
        context.restoreGState()

        super.draw(with: box, to: context)

        context.saveGState()
        context.setBlendMode(.difference)
        context.setFillColor(PDFDarkModePalette.inversionFillColor.cgColor)
        context.fill(bounds(for: box))
        context.restoreGState()
    }
}

enum PDFDarkModePalette {
    private static let fallbackPageBackgroundLevel: CGFloat = 30.0 / 255.0

    static var pageBackgroundColor: NSColor {
        resolvedDarkAquaColor(
            NSColor.textBackgroundColor,
            fallback: NSColor(white: fallbackPageBackgroundLevel, alpha: 1.0)
        )
    }

    static var inversionFillColor: NSColor {
        let background = pageBackgroundColor
            .usingColorSpace(NSColorSpace.deviceRGB)
            ?? NSColor(white: fallbackPageBackgroundLevel, alpha: 1.0)
        return NSColor(
            red: 1.0 - background.redComponent,
            green: 1.0 - background.greenComponent,
            blue: 1.0 - background.blueComponent,
            alpha: 1.0
        )
    }

    static var pageBackgroundLevel: CGFloat {
        let color = pageBackgroundColor
            .usingColorSpace(NSColorSpace.deviceRGB)
            ?? NSColor(white: fallbackPageBackgroundLevel, alpha: 1.0)
        return (color.redComponent + color.greenComponent + color.blueComponent) / 3.0
    }

    private static func resolvedDarkAquaColor(
        _ color: NSColor,
        fallback: NSColor
    ) -> NSColor {
        guard let appearance = NSAppearance(named: .darkAqua) else {
            return fallback
        }

        var resolved = fallback
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(NSColorSpace.deviceRGB) ?? fallback
        }
        return resolved
    }
}
