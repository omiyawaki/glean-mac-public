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
        let coord = context.coordinator

        nsView.setThumbnailSidebarVisible(thumbnailSidebarVisible)

        if coord.requestedURL != url || coord.requestedDarkMode != darkMode {
            coord.load(
                url: url,
                darkMode: darkMode,
                in: nsView
            )
        }

        // Match the page-background color the .difference fill produces so
        // the gutter around pages visually shares the same native dark surface.
        nsView.setPDFBackgroundColor(
            darkMode ? PDFDarkModePalette.pageBackgroundColor : .clear
        )
        nsView.setThumbnailDarkMode(darkMode)
    }

    static func dismantleNSView(_ nsView: PDFThumbnailSplitView, coordinator: Coordinator) {
        coordinator.cancelLoading()
    }

    /// PDFKit document parsing is synchronous and can take hundreds of
    /// milliseconds for large books. Keeping it on one background actor means
    /// the UI remains responsive and rapid selection never fans out into a
    /// collection of simultaneous PDF parses.
    private actor DocumentPreparer {
        static let shared = DocumentPreparer()

        func prepare(url: URL) -> PreparedDocument? {
            guard !Task.isCancelled else { return nil }
            return PreparedDocument(document: PDFDocument(url: url))
        }
    }

    private final class PreparedDocument: @unchecked Sendable {
        let document: PDFDocument?

        init(document: PDFDocument?) {
            self.document = document
        }
    }

    private final class PageClassDelegate: NSObject, PDFDocumentDelegate {
        let darkMode: Bool

        init(darkMode: Bool) {
            self.darkMode = darkMode
        }

        func classForPage() -> AnyClass {
            darkMode ? InvertedPDFPage.self : PDFPage.self
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        static let selectionDebounce = Duration.milliseconds(120)

        private(set) var requestedURL: URL?
        private(set) var requestedDarkMode = false
        private var requestGeneration = 0
        private var loadTask: Task<Void, Never>?
        private var pageClassDelegate: PageClassDelegate?

        func load(url: URL?, darkMode: Bool, in splitView: PDFThumbnailSplitView) {
            let previousURL = requestedURL
            let restorePageIndex: Int?
            if previousURL == url,
               let document = splitView.pdfView.document,
               let currentPage = splitView.pdfView.currentPage {
                let pageIndex = document.index(for: currentPage)
                restorePageIndex = pageIndex == NSNotFound ? nil : pageIndex
            } else {
                restorePageIndex = nil
            }

            requestedURL = url
            requestedDarkMode = darkMode
            requestGeneration &+= 1
            let generation = requestGeneration

            loadTask?.cancel()
            loadTask = nil
            splitView.setThumbnailDarkMode(darkMode, reloadThumbnails: false)

            guard let url else {
                splitView.setLoading(false)
                splitView.setDocument(nil)
                return
            }

            // Remove the previous document immediately so PDFKit is not still
            // drawing it while a different selection is being prepared.
            if previousURL != url {
                splitView.setDocument(nil)
                pageClassDelegate = nil
            }
            splitView.setLoading(true)

            loadTask = Task { [weak self, weak splitView] in
                do {
                    try await Task.sleep(for: Self.selectionDebounce)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let prepared = await DocumentPreparer.shared.prepare(url: url)
                guard let self, let splitView,
                      !Task.isCancelled,
                      self.requestGeneration == generation,
                      self.requestedURL == url,
                      self.requestedDarkMode == darkMode
                else { return }

                guard let document = prepared?.document else {
                    splitView.setLoading(false)
                    return
                }
                let pageClassDelegate = PageClassDelegate(darkMode: darkMode)
                document.delegate = pageClassDelegate
                self.pageClassDelegate = pageClassDelegate
                splitView.setDocument(document)
                splitView.setLoading(false)

                if let restorePageIndex,
                   restorePageIndex >= 0,
                   let page = document.page(at: restorePageIndex) {
                    splitView.pdfView.go(to: page)
                }
            }
        }

        func cancelLoading() {
            requestGeneration &+= 1
            loadTask?.cancel()
            loadTask = nil
            pageClassDelegate = nil
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
    private let loadingIndicator = NSProgressIndicator()
    private let thumbnailBackgroundView = NSVisualEffectView()
    private let configuration: PDFThumbnailSidebarConfiguration
    private var didApplyInitialThumbnailWidth = false
    private var thumbnailDarkMode: Bool?

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

    func setLoading(_ loading: Bool) {
        loadingIndicator.isHidden = !loading
        if loading {
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.stopAnimation(nil)
        }
    }

    func setPDFBackgroundColor(_ color: NSColor) {
        pdfView.backgroundColor = color
    }

    func setThumbnailDarkMode(_ darkMode: Bool, reloadThumbnails: Bool = true) {
        let changed = thumbnailDarkMode != darkMode
        thumbnailDarkMode = darkMode
        thumbnailView.layer?.filters = nil
        thumbnailView.backgroundColor = .clear
        if changed && reloadThumbnails {
            thumbnailView.reloadThumbnails()
        }
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
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(splitView)
        splitView.addArrangedSubview(mainPane)
        splitView.addArrangedSubview(thumbnailPane)

        mainPane.addSubview(pdfView)
        mainPane.addSubview(loadingIndicator)
        thumbnailPane.addSubview(thumbnailBackgroundView)
        thumbnailPane.addSubview(thumbnailView)

        thumbnailBackgroundView.material = .sidebar
        thumbnailBackgroundView.blendingMode = .withinWindow
        thumbnailBackgroundView.state = .active

        loadingIndicator.style = .spinning
        loadingIndicator.controlSize = .large
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.isHidden = true

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

            loadingIndicator.centerXAnchor.constraint(equalTo: mainPane.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: mainPane.centerYAnchor),

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
    static let initialSynchronousItemCount = 1
    static let incrementalItemBatchSize = 4
    static let incrementalItemDelay: TimeInterval = 0.01

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
    private var lastDisplayedThumbnailWidth: CGFloat = 0
    private var lastRenderedThumbnailWidth: CGFloat = 0
    private weak var thumbnailDocument: PDFDocument?
    private var thumbnailItemLoadTask: Task<Void, Never>?
    private var nextDeferredItemIndex: Int?
    private var nextDeferredRenderIndex: Int?

    override func layout() {
        super.layout()
        resizeThumbnailsIfWidthChanged()
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
        thumbnailItemLoadTask?.cancel()
        NotificationCenter.default.removeObserver(self)
        NSObject.cancelPreviousPerformRequests(withTarget: self)
    }

    func reloadThumbnails() {
        thumbnailItemLoadTask?.cancel()
        thumbnailItemLoadTask = nil
        NSObject.cancelPreviousPerformRequests(withTarget: self)
        thumbnailDocument = nil
        nextDeferredItemIndex = nil
        nextDeferredRenderIndex = nil
        thumbnailItems.forEach { $0.removeFromSuperview() }
        thumbnailItems.removeAll()

        guard let document = pdfView?.document else {
            lastDisplayedThumbnailWidth = 0
            lastRenderedThumbnailWidth = 0
            return
        }
        let thumbnailWidth = currentThumbnailWidth()
        lastDisplayedThumbnailWidth = thumbnailWidth
        lastRenderedThumbnailWidth = thumbnailWidth
        thumbnailDocument = document
        appendThumbnailItems(
            for: document,
            range: 0..<min(Self.initialSynchronousItemCount, document.pageCount),
            scheduleFirstRender: true
        )
        updateSelection()
        let nextIndex = min(Self.initialSynchronousItemCount, document.pageCount)
        if nextIndex < document.pageCount {
            nextDeferredItemIndex = nextIndex
            scheduleNextThumbnailItemBatch()
        }
    }

    private func appendThumbnailItems(
        for document: PDFDocument,
        range: Range<Int>,
        scheduleFirstRender: Bool
    ) {
        let thumbnailWidth = currentThumbnailWidth()
        let renderScale = currentRenderScale()
        let selectedPage = pdfView?.currentPage
        for index in range {
            guard let page = document.page(at: index) else { continue }
            let item = PDFThumbnailItemView(
                page: page,
                pageIndex: index,
                thumbnailSize: thumbnailDisplaySize(for: page, width: thumbnailWidth)
            )
            item.target = self
            item.action = #selector(selectThumbnail(_:))
            item.isSelected = page === selectedPage
            thumbnailItems.append(item)
            stackView.addArrangedSubview(item)
            if scheduleFirstRender && index == 0 {
                item.scheduleThumbnailRender(renderScale: renderScale)
            }
        }
    }

    private func deferredAppendNextThumbnailBatch() {
        guard let document = thumbnailDocument,
              pdfView?.document === document,
              let startIndex = nextDeferredItemIndex,
              startIndex < document.pageCount
        else {
            nextDeferredItemIndex = nil
            return
        }

        let endIndex = min(
            startIndex + Self.incrementalItemBatchSize,
            document.pageCount
        )
        appendThumbnailItems(
            for: document,
            range: startIndex..<endIndex,
            scheduleFirstRender: false
        )
        nextDeferredItemIndex = endIndex

        if endIndex < document.pageCount {
            scheduleNextThumbnailItemBatch()
        } else {
            nextDeferredItemIndex = nil
            updateSelection()
            scheduleDeferredRemainingThumbnailRender(startingAt: 1)
        }
    }

    private func scheduleNextThumbnailItemBatch() {
        thumbnailItemLoadTask?.cancel()
        thumbnailItemLoadTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(
                    for: .milliseconds(Int(Self.incrementalItemDelay * 1_000))
                )
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            self.deferredAppendNextThumbnailBatch()
        }
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

    func rerenderThumbnailsForCurrentWidth() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(deferredRerenderThumbnails),
            object: nil
        )
        guard pdfView?.document != nil else { return }
        let thumbnailWidth = currentThumbnailWidth()
        for item in thumbnailItems {
            item.resizeThumbnail(
                to: thumbnailDisplaySize(for: item.page, width: thumbnailWidth)
            )
        }
        lastDisplayedThumbnailWidth = thumbnailWidth
        lastRenderedThumbnailWidth = thumbnailWidth
        scheduleDeferredRemainingThumbnailRender(startingAt: 0)
    }

    private func resizeThumbnailsIfWidthChanged() {
        guard pdfView?.document != nil, !thumbnailItems.isEmpty else { return }
        let thumbnailWidth = currentThumbnailWidth()
        guard abs(thumbnailWidth - lastDisplayedThumbnailWidth) > 0.5 else { return }
        for item in thumbnailItems {
            item.resizeThumbnail(to: thumbnailDisplaySize(for: item.page, width: thumbnailWidth))
        }
        lastDisplayedThumbnailWidth = thumbnailWidth
        scheduleDeferredThumbnailRerender()
    }

    private func scheduleDeferredThumbnailRerender() {
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(deferredRerenderThumbnails),
            object: nil
        )
        perform(
            #selector(deferredRerenderThumbnails),
            with: nil,
            afterDelay: 0.15
        )
    }

    private func scheduleDeferredRemainingThumbnailRender(startingAt index: Int) {
        guard index < thumbnailItems.count else { return }
        nextDeferredRenderIndex = index
        NSObject.cancelPreviousPerformRequests(
            withTarget: self,
            selector: #selector(deferredRenderNextThumbnail),
            object: nil
        )
        perform(
            #selector(deferredRenderNextThumbnail),
            with: nil,
            afterDelay: 0.03
        )
    }

    @objc
    private func deferredRenderNextThumbnail() {
        guard let index = nextDeferredRenderIndex,
              index < thumbnailItems.count,
              pdfView?.document != nil
        else {
            nextDeferredRenderIndex = nil
            return
        }
        let item = thumbnailItems[index]
        item.scheduleThumbnailRender(renderScale: currentRenderScale()) { [weak self, weak item] in
            guard let self, let item,
                  self.nextDeferredRenderIndex == index,
                  index < self.thumbnailItems.count,
                  self.thumbnailItems[index] === item,
                  self.pdfView?.document != nil
            else { return }

            let nextIndex = index + 1
            self.nextDeferredRenderIndex = nextIndex
            guard nextIndex < self.thumbnailItems.count else {
                self.nextDeferredRenderIndex = nil
                return
            }
            self.perform(
                #selector(self.deferredRenderNextThumbnail),
                with: nil,
                afterDelay: 0.03
            )
        }
    }

    @objc
    private func deferredRerenderThumbnails() {
        guard pdfView?.document != nil else { return }
        let thumbnailWidth = currentThumbnailWidth()
        guard abs(thumbnailWidth - lastRenderedThumbnailWidth) > 0.5 else { return }
        rerenderThumbnailsForCurrentWidth()
    }

    private func currentRenderScale() -> CGFloat {
        max(2, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
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

    private(set) var hasRenderedThumbnail = false

    var isSelected = false {
        didSet { needsDisplay = true }
    }

    private let imageView = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var thumbnailSize: CGSize
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var renderGeneration = 0
    private var renderTask: Task<Void, Never>?

    init(
        page: PDFPage,
        pageIndex: Int,
        thumbnailSize: CGSize
    ) {
        self.page = page
        self.pageIndex = pageIndex
        self.thumbnailSize = thumbnailSize
        super.init(frame: NSRect(
            x: 0,
            y: 0,
            width: thumbnailSize.width + 32,
            height: thumbnailSize.height + 28
        ))
        configureViews(thumbnailSize: thumbnailSize)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        renderTask?.cancel()
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

    func resizeThumbnail(to thumbnailSize: CGSize) {
        self.thumbnailSize = thumbnailSize
        frame.size = CGSize(width: thumbnailSize.width + 32, height: thumbnailSize.height + 28)
        widthConstraint?.constant = thumbnailSize.width + 32
        heightConstraint?.constant = thumbnailSize.height + 28
        imageWidthConstraint?.constant = thumbnailSize.width
        imageHeightConstraint?.constant = thumbnailSize.height
        needsLayout = true
    }

    func scheduleThumbnailRender(
        renderScale: CGFloat,
        completion: (@MainActor () -> Void)? = nil
    ) {
        renderGeneration &+= 1
        let generation = renderGeneration
        renderTask?.cancel()
        hasRenderedThumbnail = false

        let request = PDFThumbnailRenderRequest(
            page: page,
            displaySize: thumbnailSize,
            renderScale: renderScale
        )
        renderTask = Task { @MainActor [weak self] in
            let result = await PDFThumbnailRenderQueue.shared.render(request)
            guard let self,
                  !Task.isCancelled,
                  self.renderGeneration == generation,
                  let image = result?.image
            else { return }
            self.imageView.image = image
            self.hasRenderedThumbnail = true
            completion?()
        }
    }

    private func configureViews(thumbnailSize: CGSize) {
        translatesAutoresizingMaskIntoConstraints = false
        imageView.translatesAutoresizingMaskIntoConstraints = false
        label.translatesAutoresizingMaskIntoConstraints = false

        imageView.image = placeholderThumbnail(size: thumbnailSize)
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

        let widthConstraint = widthAnchor.constraint(equalToConstant: thumbnailSize.width + 32)
        let heightConstraint = heightAnchor.constraint(equalToConstant: thumbnailSize.height + 28)
        let imageWidthConstraint = imageView.widthAnchor.constraint(equalToConstant: thumbnailSize.width)
        let imageHeightConstraint = imageView.heightAnchor.constraint(equalToConstant: thumbnailSize.height)
        self.widthConstraint = widthConstraint
        self.heightConstraint = heightConstraint
        self.imageWidthConstraint = imageWidthConstraint
        self.imageHeightConstraint = imageHeightConstraint

        NSLayoutConstraint.activate([
            widthConstraint,
            heightConstraint,

            imageView.topAnchor.constraint(equalTo: topAnchor),
            imageView.centerXAnchor.constraint(equalTo: centerXAnchor),
            imageWidthConstraint,
            imageHeightConstraint,

            label.leadingAnchor.constraint(equalTo: leadingAnchor),
            label.trailingAnchor.constraint(equalTo: trailingAnchor),
            label.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: 6)
        ])
    }

    private func placeholderThumbnail(size: CGSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        NSColor.textBackgroundColor.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

}

private final class PDFThumbnailRenderRequest: @unchecked Sendable {
    let page: PDFPage
    let displaySize: CGSize
    let renderScale: CGFloat

    init(page: PDFPage, displaySize: CGSize, renderScale: CGFloat) {
        self.page = page
        self.displaySize = displaySize
        self.renderScale = renderScale
    }
}

private final class PDFThumbnailRenderResult: @unchecked Sendable {
    let image: NSImage

    init(image: NSImage) {
        self.image = image
    }
}

/// PDF page rasterization can take seconds for image-heavy scans. The serial
/// actor keeps it away from AppKit's main run loop and avoids concurrent access
/// to PDFKit documents while still allowing the active selection to change.
private actor PDFThumbnailRenderQueue {
    static let shared = PDFThumbnailRenderQueue()

    func render(_ request: PDFThumbnailRenderRequest) -> PDFThumbnailRenderResult? {
        guard !Task.isCancelled else { return nil }
        let image = PDFThumbnailRasterizer.thumbnail(
            page: request.page,
            displaySize: request.displaySize,
            box: .cropBox,
            renderScale: request.renderScale
        ) ?? request.page.thumbnail(of: request.displaySize, for: .cropBox)
        guard !Task.isCancelled else { return nil }
        return PDFThumbnailRenderResult(image: image)
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
