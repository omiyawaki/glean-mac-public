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
    var thumbnailSidebarVisible: Bool = true

    func makeNSView(context: Context) -> PDFThumbnailSplitView {
        let view = PDFThumbnailSplitView()
        view.pdfView.autoScales = true
        view.pdfView.displayMode = .singlePageContinuous
        view.pdfView.displayDirection = .vertical
        return view
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func updateNSView(_ nsView: PDFThumbnailSplitView, context: Context) {
        let pdfView = nsView.pdfView
        let coord = context.coordinator
        let urlChanged = pdfView.document?.documentURL != url
        let modeChanged = coord.darkMode != darkMode
        coord.darkMode = darkMode

        nsView.setThumbnailSidebarVisible(thumbnailSidebarVisible)

        if urlChanged || modeChanged {
            let savedDest = pdfView.currentDestination
            if let url {
                let doc = PDFDocument(url: url)
                doc?.delegate = coord
                nsView.setDocument(doc)
            } else {
                nsView.setDocument(nil)
            }
            // Restore scroll position when the only thing that changed is
            // dark mode — without this the toggle jumps back to page 1.
            if modeChanged, !urlChanged, let dest = savedDest {
                pdfView.go(to: dest)
            }
        }

        // Match the page-background color the .difference fill produces so
        // the gutter around pages visually shares the same native dark surface.
        nsView.setPDFBackgroundColor(
            darkMode ? PDFDarkModePalette.pageBackgroundColor : .clear
        )
        nsView.setThumbnailDarkMode(darkMode)
    }

    final class Coordinator: NSObject, PDFDocumentDelegate {
        var darkMode = false

        func classForPage() -> AnyClass {
            darkMode ? InvertedPDFPage.self : PDFPage.self
        }
    }
}

@MainActor
final class PDFThumbnailSplitView: NSView, NSSplitViewDelegate {
    let pdfView: PDFView
    let thumbnailView: PDFThumbnailView
    let splitView = NSSplitView()
    let thumbnailPane = NSView()

    private let mainPane = NSView()
    private let thumbnailBackgroundView = NSVisualEffectView()
    private let configuration: PDFThumbnailSidebarConfiguration
    private var didApplyInitialThumbnailWidth = false

    private(set) var isThumbnailSidebarVisible = true

    init(
        pdfView: PDFView = PDFView(),
        thumbnailView: PDFThumbnailView = PDFThumbnailView(),
        configuration: PDFThumbnailSidebarConfiguration = .previewLike
    ) {
        self.pdfView = pdfView
        self.thumbnailView = thumbnailView
        self.configuration = configuration
        super.init(frame: .zero)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        applyInitialThumbnailWidthIfNeeded()
    }

    func setThumbnailSidebarVisible(_ visible: Bool) {
        guard visible != isThumbnailSidebarVisible else { return }
        isThumbnailSidebarVisible = visible
        thumbnailPane.isHidden = !visible
        splitView.adjustSubviews()
        if visible {
            applyInitialThumbnailWidthIfNeeded()
        }
    }

    func setDocument(_ document: PDFDocument?) {
        pdfView.document = document
        thumbnailView.pdfView = pdfView
    }

    func setPDFBackgroundColor(_ color: NSColor) {
        pdfView.backgroundColor = color
    }

    func setThumbnailDarkMode(_: Bool) {
        // InvertedPDFPage handles page pixels. Keep PDFThumbnailView chrome native.
        thumbnailView.layer?.filters = nil
        thumbnailView.backgroundColor = .clear
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMinCoordinate proposedMinimumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 0 else { return proposedMinimumPosition }
        return max(
            proposedMinimumPosition,
            splitView.bounds.width - configuration.maximumWidth
        )
    }

    func splitView(
        _ splitView: NSSplitView,
        constrainMaxCoordinate proposedMaximumPosition: CGFloat,
        ofSubviewAt dividerIndex: Int
    ) -> CGFloat {
        guard dividerIndex == 0 else { return proposedMaximumPosition }
        return min(
            proposedMaximumPosition,
            splitView.bounds.width - configuration.minimumWidth
        )
    }

    private func configureViews() {
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self

        mainPane.translatesAutoresizingMaskIntoConstraints = false
        thumbnailPane.translatesAutoresizingMaskIntoConstraints = false
        thumbnailBackgroundView.translatesAutoresizingMaskIntoConstraints = false
        pdfView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false

        addSubview(splitView)
        splitView.addArrangedSubview(mainPane)
        splitView.addArrangedSubview(thumbnailPane)

        mainPane.addSubview(pdfView)
        thumbnailPane.addSubview(thumbnailBackgroundView)
        thumbnailPane.addSubview(thumbnailView)

        thumbnailBackgroundView.material = .sidebar
        thumbnailBackgroundView.blendingMode = .withinWindow
        thumbnailBackgroundView.state = .active

        thumbnailView.pdfView = pdfView
        thumbnailView.thumbnailSize = configuration.thumbnailSize
        thumbnailView.maximumNumberOfColumns = 1
        thumbnailView.allowsDragging = false
        thumbnailView.allowsMultipleSelection = false
        thumbnailView.backgroundColor = .clear

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: trailingAnchor),
            splitView.topAnchor.constraint(equalTo: topAnchor),
            splitView.bottomAnchor.constraint(equalTo: bottomAnchor),

            pdfView.leadingAnchor.constraint(equalTo: mainPane.leadingAnchor),
            pdfView.trailingAnchor.constraint(equalTo: mainPane.trailingAnchor),
            pdfView.topAnchor.constraint(equalTo: mainPane.topAnchor),
            pdfView.bottomAnchor.constraint(equalTo: mainPane.bottomAnchor),

            thumbnailBackgroundView.leadingAnchor.constraint(equalTo: thumbnailPane.leadingAnchor),
            thumbnailBackgroundView.trailingAnchor.constraint(equalTo: thumbnailPane.trailingAnchor),
            thumbnailBackgroundView.topAnchor.constraint(equalTo: thumbnailPane.topAnchor),
            thumbnailBackgroundView.bottomAnchor.constraint(equalTo: thumbnailPane.bottomAnchor),

            thumbnailView.leadingAnchor.constraint(equalTo: thumbnailPane.leadingAnchor),
            thumbnailView.trailingAnchor.constraint(equalTo: thumbnailPane.trailingAnchor),
            thumbnailView.topAnchor.constraint(equalTo: thumbnailPane.topAnchor),
            thumbnailView.bottomAnchor.constraint(equalTo: thumbnailPane.bottomAnchor)
        ])
    }

    private func applyInitialThumbnailWidthIfNeeded() {
        guard !didApplyInitialThumbnailWidth,
              splitView.bounds.width > configuration.defaultWidth
        else { return }
        didApplyInitialThumbnailWidth = true
        splitView.setPosition(
            splitView.bounds.width - configuration.defaultWidth,
            ofDividerAt: 0
        )
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
