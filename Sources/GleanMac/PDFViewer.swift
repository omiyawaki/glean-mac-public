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
    let thumbnailView: PDFThumbnailSidebarView
    let splitView = NSSplitView()
    let thumbnailPane = NSView()

    private let mainPane = NSView()
    private let thumbnailBackgroundView = NSVisualEffectView()
    private let configuration: PDFThumbnailSidebarConfiguration
    private var didApplyInitialThumbnailWidth = false

    private(set) var isThumbnailSidebarVisible = true

    init(
        pdfView: PDFView = PDFView(),
        thumbnailView: PDFThumbnailSidebarView = PDFThumbnailSidebarView(),
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
        thumbnailView.layer?.filters = nil
        thumbnailView.backgroundColor = .clear
        thumbnailView.reloadThumbnails()
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
        thumbnailView.maximumThumbnailWidth = max(
            configuration.thumbnailSize.width,
            configuration.maximumWidth - PDFThumbnailSidebarView.sidebarHorizontalMargin
        )
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

@MainActor
final class PDFThumbnailSidebarView: NSScrollView {
    static let sidebarHorizontalMargin: CGFloat = 64

    weak var pdfView: PDFView? {
        didSet {
            if oldValue !== pdfView {
                updatePageChangeObserver()
            }
            reloadThumbnails()
        }
    }

    var thumbnailSize = CGSize(width: 96, height: 128) {
        didSet { reloadThumbnails() }
    }

    var maximumThumbnailWidth: CGFloat = 196 {
        didSet { reloadThumbnails() }
    }

    var maximumNumberOfColumns = 1
    var allowsDragging = false
    var allowsMultipleSelection = false

    override var backgroundColor: NSColor {
        didSet {
            drawsBackground = backgroundColor.alphaComponent > 0
            contentView.backgroundColor = backgroundColor
        }
    }

    private(set) var thumbnailItems: [PDFThumbnailItemView] = []

    private let stackView = NSStackView()
    private var lastRenderedThumbnailWidth: CGFloat = 0

    override func layout() {
        super.layout()
        reloadThumbnailsIfWidthChanged()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureViews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func reloadThumbnails() {
        thumbnailItems.forEach { $0.removeFromSuperview() }
        thumbnailItems.removeAll()

        guard let document = pdfView?.document else { return }
        let thumbnailWidth = currentThumbnailWidth()
        lastRenderedThumbnailWidth = thumbnailWidth
        let renderScale = max(2, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { continue }
            let item = PDFThumbnailItemView(
                page: page,
                pageIndex: index,
                thumbnailSize: thumbnailDisplaySize(for: page, width: thumbnailWidth),
                renderScale: renderScale
            )
            item.target = self
            item.action = #selector(selectThumbnail(_:))
            thumbnailItems.append(item)
            stackView.addArrangedSubview(item)
        }
        updateSelection()
    }

    @objc
    private func selectThumbnail(_ sender: PDFThumbnailItemView) {
        pdfView?.go(to: sender.page)
        updateSelection()
    }

    private func configureViews() {
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = false
        scrollerStyle = .overlay

        stackView.orientation = .vertical
        stackView.alignment = .centerX
        stackView.spacing = 12
        stackView.edgeInsets = NSEdgeInsets(top: 12, left: 0, bottom: 12, right: 0)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        documentView = stackView
        NSLayoutConstraint.activate([
            stackView.widthAnchor.constraint(equalTo: contentView.widthAnchor)
        ])
    }

    private func updatePageChangeObserver() {
        NotificationCenter.default.removeObserver(self)
        guard let pdfView else {
            return
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfViewPageChanged(_:)),
            name: .PDFViewPageChanged,
            object: pdfView,
        )
    }

    @objc
    private func pdfViewPageChanged(_ notification: Notification) {
        updateSelection()
    }

    private func updateSelection() {
        guard let currentPage = pdfView?.currentPage else {
            thumbnailItems.forEach { $0.isSelected = false }
            return
        }
        thumbnailItems.forEach { $0.isSelected = $0.page === currentPage }
    }

    private func reloadThumbnailsIfWidthChanged() {
        guard pdfView?.document != nil else { return }
        let thumbnailWidth = currentThumbnailWidth()
        guard abs(thumbnailWidth - lastRenderedThumbnailWidth) > 0.5 else { return }
        reloadThumbnails()
    }

    private func currentThumbnailWidth() -> CGFloat {
        let containerWidth = contentView.bounds.width > 0
            ? contentView.bounds.width
            : bounds.width
        guard containerWidth > 0 else {
            return thumbnailSize.width
        }

        let minimumThumbnailWidth = max(64, thumbnailSize.width * 0.75)
        return min(
            maximumThumbnailWidth,
            max(minimumThumbnailWidth, containerWidth - Self.sidebarHorizontalMargin)
        )
    }

    private func thumbnailDisplaySize(for page: PDFPage, width: CGFloat) -> CGSize {
        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return CGSize(
                width: width,
                height: width * thumbnailSize.height / thumbnailSize.width
            )
        }
        return CGSize(width: width, height: width * pageBounds.height / pageBounds.width)
    }
}

@MainActor
final class PDFThumbnailItemView: NSControl {
    let page: PDFPage
    let pageIndex: Int

    var thumbnailImage: NSImage? {
        imageView.image
    }

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")

    init(page: PDFPage, pageIndex: Int, thumbnailSize: CGSize, renderScale: CGFloat = 2) {
        self.page = page
        self.pageIndex = pageIndex
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: thumbnailSize.width + 32,
            height: thumbnailSize.height + 28
        ))
        configureViews(thumbnailSize: thumbnailSize, renderScale: renderScale)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func mouseDown(with event: NSEvent) {
        sendAction(action, to: target)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard isSelected else { return }
        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18).setFill()
        bounds.insetBy(dx: 4, dy: 2).fill()
    }

    private func configureViews(thumbnailSize: CGSize, renderScale: CGFloat) {
        translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = PDFThumbnailRasterizer.thumbnail(
            page: page,
            displaySize: thumbnailSize,
            box: .cropBox,
            renderScale: renderScale
        ) ?? page.thumbnail(of: thumbnailSize, for: .cropBox)
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.wantsLayer = true
        imageView.layer?.shadowColor = NSColor.black.withAlphaComponent(0.45).cgColor
        imageView.layer?.shadowOpacity = 1
        imageView.layer?.shadowRadius = 2
        imageView.layer?.shadowOffset = CGSize(width: 0, height: -1)

        label.stringValue = "\(pageIndex + 1)"
        label.alignment = .center
        label.textColor = .secondaryLabelColor
        label.font = .systemFont(ofSize: NSFont.smallSystemFontSize)

        addSubview(imageView)
        addSubview(label)

        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: thumbnailSize.width + 32),
            heightAnchor.constraint(equalToConstant: thumbnailSize.height + 28),

            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageView.widthAnchor.constraint(equalToConstant: thumbnailSize.width),
            imageView.heightAnchor.constraint(equalToConstant: thumbnailSize.height),

            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6)
        ])
    }
}

enum PDFThumbnailRasterizer {
    static func thumbnail(
        page: PDFPage,
        displaySize: CGSize,
        box: PDFDisplayBox,
        renderScale: CGFloat
    ) -> NSImage? {
        let pixelWidth = max(1, Int(ceil(displaySize.width * renderScale)))
        let pixelHeight = max(1, Int(ceil(displaySize.height * renderScale)))
        let pageBounds = page.bounds(for: box)
        guard pageBounds.width > 0, pageBounds.height > 0 else {
            return nil
        }

        let pageScale = min(
            CGFloat(pixelWidth) / pageBounds.width,
            CGFloat(pixelHeight) / pageBounds.height
        )
        let scaledSize = CGSize(
            width: pageBounds.width * pageScale,
            height: pageBounds.height * pageScale
        )
        let drawOrigin = CGPoint(
            x: (CGFloat(pixelWidth) - scaledSize.width) / 2,
            y: (CGFloat(pixelHeight) - scaledSize.height) / 2
        )
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        context.saveGState()
        context.translateBy(x: drawOrigin.x, y: drawOrigin.y)
        context.scaleBy(x: pageScale, y: pageScale)
        context.translateBy(x: -pageBounds.minX, y: -pageBounds.minY)
        context.setFillColor(NSColor.white.cgColor)
        context.fill(pageBounds)
        page.draw(with: box, to: context)
        context.restoreGState()

        guard let image = context.makeImage() else {
            return nil
        }
        return NSImage(cgImage: image, size: displaySize)
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

    override func thumbnail(of size: CGSize, for box: PDFDisplayBox) -> NSImage {
        PDFThumbnailRasterizer.thumbnail(
            page: self,
            displaySize: size,
            box: box,
            renderScale: 2
        ) ?? super.thumbnail(of: size, for: box)
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
