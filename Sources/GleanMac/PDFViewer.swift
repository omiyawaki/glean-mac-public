import SwiftUI
import PDFKit
import AppKit
import CryptoKit
import OSLog

private let libraryPDFLatencyLog = Logger(
    subsystem: "com.miyawaki.glean-mac",
    category: "pdf-latency"
)

/// Measures the path the user actually perceives: selection binding mutation
/// through the first main PDF page raster completing. Document construction or
/// cache lookup alone is not considered success.
@MainActor
final class LibraryPDFLatencyTracker {
    enum FrameSource: String {
        case pdfPage = "pdf-page"
        case cachedPreview = "cached-preview"
        case diskCachedPreview = "disk-cached-preview"
        case preparedPreview = "prepared-preview"
        case darkTransition = "dark-transition"
    }

    static let shared = LibraryPDFLatencyTracker()
    static let maximumSampleCount = 100

    private struct PendingSelection {
        let citekey: String
        let startedAt: ContinuousClock.Instant
        var expectedURL: URL?
        var requiredFrameSource: FrameSource?
        var documentCacheHit: Bool?
    }

    private var pending: PendingSelection?
    private var stablePending: PendingSelection?
    private var samples: [Double] = []
    private var cachedPreviewSamples: [Double] = []
    private var stablePDFSamples: [Double] = []
    private var stableCachedPreviewSamples: [Double] = []
    private var stableDocumentCacheHitSamples: [Double] = []

    private(set) var latestMilliseconds: Double?
    private(set) var latestCitekey: String?
    private(set) var latestFrameSource: FrameSource?
    private(set) var latestStablePDFMilliseconds: Double?
    private(set) var latestStablePDFCitekey: String?

    var sampleCount: Int { samples.count }
    var p50Milliseconds: Double? { percentile(0.50, in: samples) }
    var p95Milliseconds: Double? { percentile(0.95, in: samples) }
    var cachedPreviewP50Milliseconds: Double? {
        percentile(0.50, in: cachedPreviewSamples)
    }
    var cachedPreviewP95Milliseconds: Double? {
        percentile(0.95, in: cachedPreviewSamples)
    }
    var cachedPreviewSampleCount: Int { cachedPreviewSamples.count }
    var stablePDFSampleCount: Int { stablePDFSamples.count }
    var stablePDFP50Milliseconds: Double? {
        percentile(0.50, in: stablePDFSamples)
    }
    var stablePDFP95Milliseconds: Double? {
        percentile(0.95, in: stablePDFSamples)
    }
    var stableCachedPreviewSampleCount: Int {
        stableCachedPreviewSamples.count
    }
    var stableCachedPreviewP50Milliseconds: Double? {
        percentile(0.50, in: stableCachedPreviewSamples)
    }
    var stableCachedPreviewP95Milliseconds: Double? {
        percentile(0.95, in: stableCachedPreviewSamples)
    }
    var stableDocumentCacheHitSampleCount: Int {
        stableDocumentCacheHitSamples.count
    }
    var stableDocumentCacheHitP50Milliseconds: Double? {
        percentile(0.50, in: stableDocumentCacheHitSamples)
    }
    var stableDocumentCacheHitP95Milliseconds: Double? {
        percentile(0.95, in: stableDocumentCacheHitSamples)
    }

    func selectionChanged(to citekey: String?) {
        guard let citekey else {
            pending = nil
            stablePending = nil
            return
        }
        let selection = PendingSelection(
            citekey: citekey,
            startedAt: .now,
            expectedURL: nil,
            documentCacheHit: nil
        )
        pending = selection
        stablePending = selection
    }

    func expectFirstFrame(
        citekey: String?,
        url: URL,
        requiredFrameSource: FrameSource? = nil,
        documentCacheHit: Bool? = nil
    ) {
        guard let citekey,
              var pending,
              pending.citekey == citekey
        else { return }
        pending.expectedURL = url.standardizedFileURL
        pending.requiredFrameSource = requiredFrameSource
        if let documentCacheHit {
            pending.documentCacheHit = documentCacheHit
        }
        self.pending = pending
        if var stablePending, stablePending.citekey == citekey {
            stablePending.expectedURL = url.standardizedFileURL
            stablePending.requiredFrameSource = requiredFrameSource
            if let documentCacheHit {
                stablePending.documentCacheHit = documentCacheHit
            }
            self.stablePending = stablePending
        }
    }

    func recordFirstPageDraw(
        documentURL: URL,
        source: FrameSource = .pdfPage,
        finishedAt: ContinuousClock.Instant = .now
    ) {
        guard let pending,
              pending.expectedURL == documentURL.standardizedFileURL,
              pending.requiredFrameSource == nil || source == pending.requiredFrameSource
        else { return }

        let milliseconds = (finishedAt - pending.startedAt) / .milliseconds(1)
        self.pending = nil
        latestMilliseconds = milliseconds
        latestCitekey = pending.citekey
        latestFrameSource = source
        samples.append(milliseconds)
        if source == .cachedPreview {
            cachedPreviewSamples.append(milliseconds)
        }
        if samples.count > Self.maximumSampleCount {
            samples.removeFirst(samples.count - Self.maximumSampleCount)
        }
        if cachedPreviewSamples.count > Self.maximumSampleCount {
            cachedPreviewSamples.removeFirst(
                cachedPreviewSamples.count - Self.maximumSampleCount
            )
        }
        libraryPDFLatencyLog.notice(
            "selection-to-first-visible-pixels citekey=\(pending.citekey, privacy: .public) source=\(source.rawValue, privacy: .public) ms=\(milliseconds, privacy: .public)"
        )
    }

    func recordStablePDFReveal(
        documentURL: URL,
        finishedAt: ContinuousClock.Instant = .now
    ) {
        guard let stablePending,
              stablePending.expectedURL == documentURL.standardizedFileURL
        else { return }
        let milliseconds = (finishedAt - stablePending.startedAt) / .milliseconds(1)
        self.stablePending = nil
        latestStablePDFMilliseconds = milliseconds
        latestStablePDFCitekey = stablePending.citekey
        stablePDFSamples.append(milliseconds)
        if stablePending.requiredFrameSource == .cachedPreview
            || stablePending.requiredFrameSource == .diskCachedPreview {
            stableCachedPreviewSamples.append(milliseconds)
        }
        if stablePending.documentCacheHit == true {
            stableDocumentCacheHitSamples.append(milliseconds)
        }
        if stablePDFSamples.count > Self.maximumSampleCount {
            stablePDFSamples.removeFirst(
                stablePDFSamples.count - Self.maximumSampleCount
            )
        }
        if stableCachedPreviewSamples.count > Self.maximumSampleCount {
            stableCachedPreviewSamples.removeFirst(
                stableCachedPreviewSamples.count - Self.maximumSampleCount
            )
        }
        if stableDocumentCacheHitSamples.count > Self.maximumSampleCount {
            stableDocumentCacheHitSamples.removeFirst(
                stableDocumentCacheHitSamples.count - Self.maximumSampleCount
            )
        }
        libraryPDFLatencyLog.notice(
            "selection-to-stable-live-pdf citekey=\(stablePending.citekey, privacy: .public) ms=\(milliseconds, privacy: .public)"
        )
    }

    func reset() {
        pending = nil
        stablePending = nil
        samples = []
        cachedPreviewSamples = []
        stablePDFSamples = []
        stableCachedPreviewSamples = []
        stableDocumentCacheHitSamples = []
        latestMilliseconds = nil
        latestCitekey = nil
        latestFrameSource = nil
        latestStablePDFMilliseconds = nil
        latestStablePDFCitekey = nil
    }

    private func percentile(_ fraction: Double, in values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let index = min(
            sorted.count - 1,
            max(0, Int(ceil(fraction * Double(sorted.count))) - 1)
        )
        return sorted[index]
    }
}

/// Thumbnail rasterization uses the same PDFPage.draw API as the onscreen
/// PDFView. Mark those calls so they cannot satisfy the first-visible-frame
/// measurement before the main page itself has appeared.
private enum PDFThumbnailRenderingContext {
    private static let key = "com.miyawaki.glean-mac.thumbnail-render"

    static var isRendering: Bool {
        Thread.current.threadDictionary[key] as? Bool == true
    }

    static func perform<T>(_ body: () -> T) -> T {
        let dictionary = Thread.current.threadDictionary
        let previous = dictionary[key]
        dictionary[key] = true
        defer {
            if let previous {
                dictionary[key] = previous
            } else {
                dictionary.removeObject(forKey: key)
            }
        }
        return body()
    }
}

private enum PDFPageDrawReporter {
    static let notification = Notification.Name("GleanPDFPageDidDraw")

    static func report(_ page: PDFPage) {
        guard !PDFThumbnailRenderingContext.isRendering,
              let documentURL = page.document?.documentURL
        else { return }
        let finishedAt = ContinuousClock.now
        Task { @MainActor in
            LibraryPDFLatencyTracker.shared.recordFirstPageDraw(
                documentURL: documentURL,
                finishedAt: finishedAt
            )
            NotificationCenter.default.post(
                name: notification,
                object: nil,
                userInfo: ["documentURL": documentURL]
            )
        }
    }
}

final class LatencyReportingPDFPage: PDFPage {
    override func draw(with box: PDFDisplayBox, to context: CGContext) {
        super.draw(with: box, to: context)
        PDFPageDrawReporter.report(self)
    }
}

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

struct PDFFileCacheDescriptor: Sendable {
    let identity: String
    let estimatedCost: Int

    init(url: URL) {
        let standardizedURL = url.standardizedFileURL
        let attributes = try? FileManager.default.attributesOfItem(
            atPath: standardizedURL.path
        )
        let fileSize = (attributes?[.size] as? NSNumber)?.intValue
        let modificationDate = attributes?[.modificationDate] as? Date
        let modificationStamp = modificationDate?.timeIntervalSinceReferenceDate.bitPattern ?? 0

        identity = [
            standardizedURL.path,
            String(fileSize ?? 0),
            String(modificationStamp)
        ].joined(separator: "|")
        estimatedCost = max(fileSize ?? 0, 1)
    }
}

/// Retains only the rendered pixels most likely to be revisited. `NSCache`
/// automatically yields entries under memory pressure in addition to these
/// explicit count and decoded-pixel limits.
private final class PDFThumbnailMemoryCache: @unchecked Sendable {
    static let shared = PDFThumbnailMemoryCache()
    static let totalCostLimit = 96 * 1_024 * 1_024
    static let countLimit = 512

    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.totalCostLimit = Self.totalCostLimit
        cache.countLimit = Self.countLimit
        cache.name = "Glean PDF thumbnails"
    }

    func image(for key: String) -> NSImage? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ image: NSImage, for key: String, cost: Int) {
        cache.setObject(image, forKey: key as NSString, cost: max(cost, 1))
    }
}

private final class PDFWarmPreviewMemoryCache: @unchecked Sendable {
    static let shared = PDFWarmPreviewMemoryCache()
    static let totalCostLimit = 128 * 1_024 * 1_024
    static let countLimit = 16

    private let cache = NSCache<NSString, PDFWarmPreview>()

    private init() {
        cache.totalCostLimit = Self.totalCostLimit
        cache.countLimit = Self.countLimit
        cache.name = "Glean warm PDF page previews"
    }

    func preview(for key: String) -> PDFWarmPreview? {
        cache.object(forKey: key as NSString)
    }

    func insert(_ preview: PDFWarmPreview, for key: String, cost: Int) {
        cache.setObject(preview, forKey: key as NSString, cost: max(cost, 1))
    }
}

struct PDFWarmPreviewPlacement: Codable, Equatable, Sendable {
    static let viewportTolerance: CGFloat = 0.5

    let viewportWidth: Double
    let viewportHeight: Double
    let pageX: Double
    let pageY: Double
    let pageWidth: Double
    let pageHeight: Double

    init(viewportSize: CGSize, pageRect: CGRect) {
        viewportWidth = Double(viewportSize.width)
        viewportHeight = Double(viewportSize.height)
        pageX = Double(pageRect.minX)
        pageY = Double(pageRect.minY)
        pageWidth = Double(pageRect.width)
        pageHeight = Double(pageRect.height)
    }

    func pageRect(
        for viewportSize: CGSize,
        tolerance: CGFloat = Self.viewportTolerance
    ) -> CGRect? {
        guard abs(CGFloat(viewportWidth) - viewportSize.width) <= tolerance,
              abs(CGFloat(viewportHeight) - viewportSize.height) <= tolerance,
              pageWidth > 0,
              pageHeight > 0
        else { return nil }
        return CGRect(
            x: CGFloat(pageX),
            y: CGFloat(pageY),
            width: CGFloat(pageWidth),
            height: CGFloat(pageHeight)
        )
    }

    func matches(
        viewportSize: CGSize,
        pageRect: CGRect,
        tolerance: CGFloat = Self.viewportTolerance
    ) -> Bool {
        guard let cachedRect = self.pageRect(
            for: viewportSize,
            tolerance: tolerance
        ) else { return false }
        return abs(cachedRect.minX - pageRect.minX) <= tolerance
            && abs(cachedRect.minY - pageRect.minY) <= tolerance
            && abs(cachedRect.width - pageRect.width) <= tolerance
            && abs(cachedRect.height - pageRect.height) <= tolerance
    }
}

final class PDFWarmPreview: NSObject, @unchecked Sendable {
    let image: NSImage
    let pageIndex: Int
    let placement: PDFWarmPreviewPlacement?

    init(
        image: NSImage,
        pageIndex: Int,
        placement: PDFWarmPreviewPlacement? = nil
    ) {
        self.image = image
        self.pageIndex = pageIndex
        self.placement = placement
    }
}

/// A small persistent bridge image makes a paper that has been opened before
/// feel warm even after relaunching Glean. Entries are keyed by the PDF's path,
/// size, modification date, and dark-mode state, so changed files never reuse
/// stale pixels. All file IO and image encoding/decoding stays off the main
/// actor.
actor PDFWarmPreviewDiskCache {
    private struct StoredPreview: Codable {
        let version: Int
        let pageIndex: Int
        let placement: PDFWarmPreviewPlacement
        let pngData: Data
    }

    static let shared = PDFWarmPreviewDiskCache()
    static let currentVersion = 2
    static let countLimit = 256
    static let totalSizeLimit = 256 * 1_024 * 1_024

    private let directory: URL
    private let countLimit: Int
    private let totalSizeLimit: Int

    init(
        directory: URL? = nil,
        countLimit: Int = PDFWarmPreviewDiskCache.countLimit,
        totalSizeLimit: Int = PDFWarmPreviewDiskCache.totalSizeLimit
    ) {
        if let directory {
            self.directory = directory
        } else {
            let base = FileManager.default.urls(
                for: .cachesDirectory,
                in: .userDomainMask
            ).first ?? FileManager.default.homeDirectoryForCurrentUser
            self.directory = base
                .appendingPathComponent("Glean", isDirectory: true)
                .appendingPathComponent("PDFWarmPreviews", isDirectory: true)
        }
        self.countLimit = max(1, countLimit)
        self.totalSizeLimit = max(1, totalSizeLimit)
    }

    func preview(for key: String) -> PDFWarmPreview? {
        let url = entryURL(for: key)
        guard let data = try? Data(contentsOf: url),
              let stored = try? PropertyListDecoder().decode(
                StoredPreview.self,
                from: data
              ),
              stored.version == Self.currentVersion,
              let image = NSImage(data: stored.pngData)
        else { return nil }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        return PDFWarmPreview(
            image: image,
            pageIndex: stored.pageIndex,
            placement: stored.placement
        )
    }

    func insert(_ preview: PDFWarmPreview, for key: String) {
        guard let placement = preview.placement,
              let tiffData = preview.image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData),
              let pngData = bitmap.representation(using: .png, properties: [:])
        else { return }
        let stored = StoredPreview(
            version: Self.currentVersion,
            pageIndex: preview.pageIndex,
            placement: placement,
            pngData: pngData
        )
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        guard let data = try? encoder.encode(stored) else { return }
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
            try data.write(to: entryURL(for: key), options: .atomic)
            pruneIfNeeded()
        } catch {
            libraryPDFLatencyLog.error(
                "Could not persist PDF preview: \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func entryURL(for key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return directory.appendingPathComponent("\(digest).plist")
    }

    private func pruneIfNeeded() {
        let keys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        guard var entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        ).compactMap({ url -> (url: URL, date: Date, size: Int)? in
            guard let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true
            else { return nil }
            return (
                url,
                values.contentModificationDate ?? .distantPast,
                values.fileSize ?? 0
            )
        }) else { return }
        entries.sort { $0.date > $1.date }
        var retainedSize = 0
        for (index, entry) in entries.enumerated() {
            retainedSize += entry.size
            if index >= countLimit || retainedSize > totalSizeLimit {
                try? FileManager.default.removeItem(at: entry.url)
            }
        }
    }
}

private final class PDFWarmPreviewRequest: @unchecked Sendable {
    let page: PDFPage
    let displaySize: CGSize
    let renderScale: CGFloat
    let cacheKey: String
    let pixelCost: Int
    let pageIndex: Int
    let placement: PDFWarmPreviewPlacement
    let persistToDisk: Bool

    init(
        page: PDFPage,
        displaySize: CGSize,
        renderScale: CGFloat,
        cacheKey: String,
        pixelCost: Int,
        pageIndex: Int,
        placement: PDFWarmPreviewPlacement,
        persistToDisk: Bool
    ) {
        self.page = page
        self.displaySize = displaySize
        self.renderScale = renderScale
        self.cacheKey = cacheKey
        self.pixelCost = pixelCost
        self.pageIndex = pageIndex
        self.placement = placement
        self.persistToDisk = persistToDisk
    }
}

private actor PDFWarmPreviewRenderQueue {
    static let shared = PDFWarmPreviewRenderQueue()

    func prepare(_ request: PDFWarmPreviewRequest) async {
        guard !Task.isCancelled else { return }
        let image = PDFThumbnailRenderingContext.perform {
            PDFThumbnailRasterizer.thumbnail(
                page: request.page,
                displaySize: request.displaySize,
                box: .cropBox,
                renderScale: request.renderScale
            )
        }
        guard let image, !Task.isCancelled else { return }
        let preview = PDFWarmPreview(
            image: image,
            pageIndex: request.pageIndex,
            placement: request.placement
        )
        PDFWarmPreviewMemoryCache.shared.insert(
            preview,
            for: request.cacheKey,
            cost: request.pixelCost
        )
        if request.persistToDisk {
            await PDFWarmPreviewDiskCache.shared.insert(
                preview,
                for: request.cacheKey
            )
        }
    }
}

@MainActor
private final class PDFWarmPreviewView: NSView {
    var image: NSImage?
    var documentURL: URL?
    var frameSource: LibraryPDFLatencyTracker.FrameSource?
    var backgroundColor: NSColor = .clear
    var onFirstDraw: ((URL, LibraryPDFLatencyTracker.FrameSource, ContinuousClock.Instant) -> Void)?
    private var targetPageRect: NSRect?

    private(set) var reportedCurrentImage = false

    override var isOpaque: Bool {
        backgroundColor.alphaComponent >= 1
    }

    func show(
        image: NSImage,
        documentURL: URL,
        frameSource: LibraryPDFLatencyTracker.FrameSource,
        pageRect: NSRect
    ) {
        self.image = image
        self.documentURL = documentURL
        self.frameSource = frameSource
        targetPageRect = pageRect
        reportedCurrentImage = false
        isHidden = false
        needsDisplay = true
    }

    func showBackground(documentURL: URL) {
        image = nil
        self.documentURL = documentURL
        frameSource = nil
        targetPageRect = nil
        reportedCurrentImage = false
        isHidden = false
        needsDisplay = true
    }

    func hide() {
        isHidden = true
        image = nil
        documentURL = nil
        frameSource = nil
        targetPageRect = nil
        reportedCurrentImage = false
    }

    func alignImage(to pageRect: NSRect?) {
        guard targetPageRect != pageRect else { return }
        targetPageRect = pageRect
        needsDisplay = true
    }

    var currentImageRect: NSRect? {
        guard image != nil else { return nil }
        return targetPageRect
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        backgroundColor.setFill()
        dirtyRect.fill()
        guard let image,
              let targetPageRect,
              targetPageRect.width > 0,
              targetPageRect.height > 0
        else { return }

        image.draw(
            in: targetPageRect,
            from: .zero,
            operation: .copy,
            fraction: 1,
            respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high]
        )

        if !reportedCurrentImage, let documentURL, let frameSource {
            reportedCurrentImage = true
            onFirstDraw?(documentURL, frameSource, .now)
        }
    }

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
    var citekey: String? = nil
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

        // Establish the destination surface before PDFKit sees a new
        // document. Some PDFs expose PDFKit's white page layer synchronously
        // during assignment, before the first inverted tile is ready.
        nsView.setPDFBackgroundColor(
            darkMode ? PDFDarkModePalette.pageBackgroundColor : .clear
        )
        nsView.setThumbnailDarkMode(darkMode)

        if coord.requestedURL != url
            || coord.requestedCitekey != citekey
            || coord.requestedDarkMode != darkMode {
            coord.load(
                url: url,
                citekey: citekey,
                darkMode: darkMode,
                in: nsView
            )
        }
    }

    static func dismantleNSView(_ nsView: PDFThumbnailSplitView, coordinator: Coordinator) {
        coordinator.cancelLoading()
    }

#if DEBUG
    /// Deterministic cache-pressure hook for transition regression tests.
    /// Production code relies on NSCache's normal count and memory limits.
    static func evictPreparedDocumentsForTesting() {
        DocumentMemoryCache.shared.removeAll()
    }
#endif

    private final class PreparedDocument: @unchecked Sendable {
        let document: PDFDocument
        let initialPreview: PDFWarmPreview?
        private let pageClassDelegate: PageClassDelegate

        init(
            document: PDFDocument,
            initialPreview: PDFWarmPreview?,
            pageClassDelegate: PageClassDelegate
        ) {
            self.document = document
            self.initialPreview = initialPreview
            self.pageClassDelegate = pageClassDelegate
        }
    }

    private final class PageClassDelegate: NSObject, PDFDocumentDelegate {
        let darkMode: Bool

        init(darkMode: Bool) {
            self.darkMode = darkMode
        }

        func classForPage() -> AnyClass {
            darkMode ? InvertedPDFPage.self : LatencyReportingPDFPage.self
        }
    }

    /// Parsed documents are lazy, so on-disk file size is a deliberately
    /// conservative memory-cost proxy. This retains at most a few recent
    /// papers and lets `NSCache` discard them earlier under memory pressure.
    private final class DocumentMemoryCache: @unchecked Sendable {
        static let shared = DocumentMemoryCache()
        static let totalCostLimit = 512 * 1_024 * 1_024
        static let countLimit = 8

        private let cache = NSCache<NSString, PreparedDocument>()

        private init() {
            cache.totalCostLimit = Self.totalCostLimit
            cache.countLimit = Self.countLimit
            cache.name = "Glean parsed PDF documents"
        }

        func document(
            for descriptor: PDFFileCacheDescriptor,
            darkMode: Bool
        ) -> PreparedDocument? {
            cache.object(forKey: key(for: descriptor, darkMode: darkMode))
        }

        func insert(
            _ document: PreparedDocument,
            for descriptor: PDFFileCacheDescriptor,
            darkMode: Bool
        ) {
            guard descriptor.estimatedCost <= Self.totalCostLimit else { return }
            cache.setObject(
                document,
                forKey: key(for: descriptor, darkMode: darkMode),
                cost: descriptor.estimatedCost
            )
        }

        func removeAll() {
            cache.removeAllObjects()
        }

        private func key(
            for descriptor: PDFFileCacheDescriptor,
            darkMode: Bool
        ) -> NSString {
            "\(descriptor.identity)|dark:\(darkMode)" as NSString
        }
    }

    /// PDFKit document parsing is synchronous and can take hundreds of
    /// milliseconds for large books. Keeping cache misses on one background
    /// actor means rapid selection never fans out into simultaneous parses.
    private actor DocumentPreparer {
        static let shared = DocumentPreparer()
        static let maximumInitialPreviewFileSize = 10 * 1_024 * 1_024
        static let initialPreviewWidth: CGFloat = 420

        func prepare(
            url: URL,
            darkMode: Bool,
            descriptor: PDFFileCacheDescriptor
        ) -> PreparedDocument? {
            if let cached = DocumentMemoryCache.shared.document(
                for: descriptor,
                darkMode: darkMode
            ) {
                return cached
            }
            guard !Task.isCancelled else { return nil }

            let pageClassDelegate = PageClassDelegate(darkMode: darkMode)
            guard let document = PDFDocument(url: url) else { return nil }
            document.delegate = pageClassDelegate
            let initialPreview = makeInitialPreview(
                for: document,
                darkMode: darkMode,
                descriptor: descriptor
            )
            let prepared = PreparedDocument(
                document: document,
                initialPreview: initialPreview,
                pageClassDelegate: pageClassDelegate
            )

            // Parsing cannot be interrupted once PDFKit starts. Preserve a
            // completed result even if its original selection was superseded;
            // revisiting that paper can then be immediate.
            DocumentMemoryCache.shared.insert(
                prepared,
                for: descriptor,
                darkMode: darkMode
            )
            return prepared
        }

        /// Produce useful dark pixels before the main actor hands the document
        /// to PDFKit. The preview is intentionally modest resolution: it only
        /// bridges the first tile render, while the normal warm-preview path
        /// replaces it with a Retina image after the live page is onscreen.
        private func makeInitialPreview(
            for document: PDFDocument,
            darkMode: Bool,
            descriptor: PDFFileCacheDescriptor
        ) -> PDFWarmPreview? {
            guard darkMode,
                  descriptor.estimatedCost <= Self.maximumInitialPreviewFileSize,
                  let page = document.page(at: 0)
            else { return nil }
            let pageBounds = page.bounds(for: .cropBox)
            guard pageBounds.width > 0, pageBounds.height > 0 else { return nil }
            let displaySize = CGSize(
                width: Self.initialPreviewWidth,
                height: Self.initialPreviewWidth * pageBounds.height / pageBounds.width
            )
            guard let image = PDFThumbnailRasterizer.thumbnail(
                page: page,
                displaySize: displaySize,
                box: .cropBox,
                renderScale: 1
            ) else { return nil }
            return PDFWarmPreview(image: image, pageIndex: 0)
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        static let selectionDebounce = Duration.milliseconds(16)

        private(set) var requestedURL: URL?
        private(set) var requestedCitekey: String?
        private(set) var requestedDarkMode = false
        private var requestGeneration = 0
        private var loadTask: Task<Void, Never>?

        func load(
            url: URL?,
            citekey: String? = nil,
            darkMode: Bool,
            in splitView: PDFThumbnailSplitView
        ) {
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
            requestedCitekey = citekey
            requestedDarkMode = darkMode
            requestGeneration &+= 1
            let generation = requestGeneration

            loadTask?.cancel()
            loadTask = nil
            splitView.setPDFBackgroundColor(
                darkMode ? PDFDarkModePalette.pageBackgroundColor : .clear
            )
            splitView.setThumbnailDarkMode(darkMode, reloadThumbnails: false)

            guard let url else {
                splitView.setLoading(false)
                splitView.clearWarmPreview()
                splitView.setDocument(nil)
                return
            }

            let descriptor = PDFFileCacheDescriptor(url: url)
            let warmPreviewPageIndex = splitView.prepareForDocument(
                url: url,
                descriptor: descriptor,
                darkMode: darkMode
            )
            let hasWarmPreview = warmPreviewPageIndex != nil
            let cachedDocument = DocumentMemoryCache.shared.document(
                for: descriptor,
                darkMode: darkMode
            )
            LibraryPDFLatencyTracker.shared.expectFirstFrame(
                citekey: citekey,
                url: url,
                requiredFrameSource: hasWarmPreview
                    ? .cachedPreview
                    : (darkMode ? .darkTransition : nil),
                documentCacheHit: cachedDocument != nil
            )
            // A memory-warm document can establish PDFKit's exact page frame
            // synchronously. Defer that preview's first draw until after the
            // cached document is assigned so the cover never changes size.
            if !hasWarmPreview {
                splitView.displayTransitionCoverIfNeeded()
            }
            if let cached = cachedDocument {
                splitView.setDocument(cached.document)
                if !darkMode {
                    splitView.setLoading(false)
                }
                restorePageIfNeeded(
                    warmPreviewPageIndex ?? restorePageIndex,
                    in: cached.document,
                    splitView: splitView
                )
                splitView.displayTransitionCoverIfNeeded()
                return
            }

            // Remove the previous document immediately so PDFKit is not still
            // drawing it while a different selection is being prepared.
            if previousURL != url {
                splitView.setDocument(nil, preservingThumbnails: true)
            }
            splitView.setLoading(true)

            loadTask = Task { [weak self, weak splitView] in
                var transitionPreviewPageIndex = warmPreviewPageIndex
                if darkMode,
                   transitionPreviewPageIndex == nil,
                   let diskPreview = await PDFWarmPreviewDiskCache.shared.preview(
                       for: "\(descriptor.identity)|dark:\(darkMode)"
                   ) {
                    guard let self, let splitView,
                          !Task.isCancelled,
                          self.requestGeneration == generation,
                          self.requestedURL == url,
                          self.requestedDarkMode == darkMode
                    else { return }
                    LibraryPDFLatencyTracker.shared.expectFirstFrame(
                        citekey: citekey,
                        url: url,
                        requiredFrameSource: .diskCachedPreview
                    )
                    transitionPreviewPageIndex = splitView.showTransitionPreview(
                        diskPreview,
                        url: url,
                        descriptor: descriptor,
                        darkMode: darkMode,
                        frameSource: .diskCachedPreview
                    )
                }
                do {
                    try await Task.sleep(for: Self.selectionDebounce)
                } catch {
                    return
                }
                guard !Task.isCancelled else { return }

                let prepared = await DocumentPreparer.shared.prepare(
                    url: url,
                    darkMode: darkMode,
                    descriptor: descriptor
                )
                guard let self, let splitView,
                      !Task.isCancelled,
                      self.requestGeneration == generation,
                      self.requestedURL == url,
                      self.requestedDarkMode == darkMode
                else { return }

                guard let prepared else {
                    splitView.cancelDocumentTransition()
                    return
                }
                let preparedPreviewPageIndex: Int?
                if transitionPreviewPageIndex == nil,
                   let preview = prepared.initialPreview {
                    LibraryPDFLatencyTracker.shared.expectFirstFrame(
                        citekey: citekey,
                        url: url,
                        requiredFrameSource: .preparedPreview
                    )
                    preparedPreviewPageIndex = splitView.showTransitionPreview(
                        preview,
                        url: url,
                        descriptor: descriptor,
                        darkMode: darkMode,
                        frameSource: .preparedPreview,
                        displayImmediately: false
                    )
                } else {
                    preparedPreviewPageIndex = nil
                }
                splitView.setDocument(prepared.document)
                if !darkMode {
                    splitView.setLoading(false)
                }
                self.restorePageIfNeeded(
                    transitionPreviewPageIndex
                        ?? preparedPreviewPageIndex
                        ?? restorePageIndex,
                    in: prepared.document,
                    splitView: splitView
                )
                splitView.displayTransitionCoverIfNeeded()
            }
        }

        private func restorePageIfNeeded(
            _ pageIndex: Int?,
            in document: PDFDocument,
            splitView: PDFThumbnailSplitView
        ) {
            guard let pageIndex,
                  pageIndex >= 0,
                  let page = document.page(at: pageIndex)
            else { return }
            splitView.pdfView.go(to: page)
            splitView.alignTransitionCoverToCurrentPage()
        }

        func cancelLoading() {
            requestGeneration &+= 1
            loadTask?.cancel()
            loadTask = nil
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
    private let warmPreviewView = PDFWarmPreviewView()
    private let thumbnailBackgroundView = NSVisualEffectView()
    private let configuration: PDFThumbnailSidebarConfiguration
    private var didApplyInitialThumbnailWidth = false
    private var thumbnailDarkMode: Bool?
    private var warmPreviewKey: String?
    private var warmPreviewTask: Task<Void, Never>?
    private var transitionCoverDismissalTask: Task<Void, Never>?
    private var scheduledWarmPreviewPageIndex: Int?
    private var onscreenPageDidDraw = false
    private var pendingWarmPreview: (
        preview: PDFWarmPreview,
        url: URL,
        source: LibraryPDFLatencyTracker.FrameSource
    )?
    private var presentedWarmPreview: PDFWarmPreview?

    private(set) var isThumbnailSidebarVisible = true
    private(set) var isLoading = false
    private(set) var latestPresentedTransitionFrameSource:
        LibraryPDFLatencyTracker.FrameSource?

    var isTransitionCoverVisible: Bool { !warmPreviewView.isHidden }
    var isTransitionCoverOpaque: Bool { warmPreviewView.isOpaque }
    var transitionCoverHasImage: Bool { warmPreviewView.image != nil }
    var transitionCoverFrameSource: LibraryPDFLatencyTracker.FrameSource? {
        warmPreviewView.frameSource
    }
    var transitionCoverBackgroundColor: NSColor { warmPreviewView.backgroundColor }
    var transitionCoverImageRect: NSRect? { warmPreviewView.currentImageRect }
    var loadingIndicatorStyle: NSProgressIndicator.Style { loadingIndicator.style }
    var loadingIndicatorIsIndeterminate: Bool { loadingIndicator.isIndeterminate }

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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(pdfPageDidDraw(_:)),
            name: PDFPageDrawReporter.notification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        warmPreviewTask?.cancel()
        transitionCoverDismissalTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }

    override func layout() {
        super.layout()
        applyInitialThumbnailWidthIfNeeded()
        demoteWarmPreviewIfViewportChangedBeforeDocumentLoad()
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

    func setDocument(
        _ document: PDFDocument?,
        preservingThumbnails: Bool = false
    ) {
        guard pdfView.document !== document else { return }
        pdfView.document = document
        if document != nil || !preservingThumbnails {
            thumbnailView.reloadThumbnails()
        }
        promotePendingWarmPreviewIfPossible()
        alignTransitionCoverToCurrentPage()
    }

    @discardableResult
    func prepareForDocument(
        url: URL,
        descriptor: PDFFileCacheDescriptor,
        darkMode: Bool
    ) -> Int? {
        // Keep this invariant local to the transition itself. Coordinators and
        // tests may enter here directly, and no caller should be able to expose
        // a transparent cover while preparing a dark page.
        setPDFBackgroundColor(
            darkMode ? PDFDarkModePalette.pageBackgroundColor : .clear
        )
        warmPreviewTask?.cancel()
        warmPreviewTask = nil
        transitionCoverDismissalTask?.cancel()
        transitionCoverDismissalTask = nil
        scheduledWarmPreviewPageIndex = nil
        onscreenPageDidDraw = false
        latestPresentedTransitionFrameSource = nil
        pendingWarmPreview = nil
        presentedWarmPreview = nil
        let key = "\(descriptor.identity)|dark:\(darkMode)"
        warmPreviewKey = key
        guard let preview = PDFWarmPreviewMemoryCache.shared.preview(for: key) else {
            if darkMode {
                warmPreviewView.showBackground(
                    documentURL: url.standardizedFileURL
                )
            } else {
                warmPreviewView.hide()
            }
            setLoading(true)
            return nil
        }
        stageWarmPreview(
            preview,
            url: url,
            source: .cachedPreview,
            displayImmediately: false
        )
        return preview.pageIndex
    }

    @discardableResult
    fileprivate func showTransitionPreview(
        _ preview: PDFWarmPreview,
        url: URL,
        descriptor: PDFFileCacheDescriptor,
        darkMode: Bool,
        frameSource: LibraryPDFLatencyTracker.FrameSource,
        displayImmediately: Bool = true
    ) -> Int? {
        let key = "\(descriptor.identity)|dark:\(darkMode)"
        guard warmPreviewKey == key else { return nil }
        let pixelCost = preview.image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ).map { $0.width * $0.height * 4 } ?? 1
        PDFWarmPreviewMemoryCache.shared.insert(
            preview,
            for: key,
            cost: pixelCost
        )
        stageWarmPreview(
            preview,
            url: url,
            source: frameSource,
            displayImmediately: displayImmediately
        )
        return preview.pageIndex
    }

    private func stageWarmPreview(
        _ preview: PDFWarmPreview,
        url: URL,
        source: LibraryPDFLatencyTracker.FrameSource,
        displayImmediately: Bool
    ) {
        let standardizedURL = url.standardizedFileURL
        if let pageRect = preview.placement?.pageRect(
            for: warmPreviewView.bounds.size
        ) {
            pendingWarmPreview = nil
            presentedWarmPreview = preview
            warmPreviewView.show(
                image: preview.image,
                documentURL: standardizedURL,
                frameSource: source,
                pageRect: pageRect
            )
            latestPresentedTransitionFrameSource = source
            setLoading(false)
        } else {
            pendingWarmPreview = (preview, standardizedURL, source)
            presentedWarmPreview = nil
            warmPreviewView.showBackground(documentURL: standardizedURL)
            latestPresentedTransitionFrameSource = nil
            setLoading(true)
        }
        if displayImmediately {
            warmPreviewView.displayIfNeeded()
        }
    }

    private func promotePendingWarmPreviewIfPossible() {
        guard let pendingWarmPreview else { return }
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        guard let pageRect = currentPDFPageRectInTransitionCover else { return }
        self.pendingWarmPreview = nil
        presentedWarmPreview = pendingWarmPreview.preview
        warmPreviewView.show(
            image: pendingWarmPreview.preview.image,
            documentURL: pendingWarmPreview.url,
            frameSource: pendingWarmPreview.source,
            pageRect: pageRect
        )
        latestPresentedTransitionFrameSource = pendingWarmPreview.source
        setLoading(false)
    }

    /// A cached page rectangle is valid only in the viewport where PDFKit
    /// produced it. Window and split-view changes can happen while the next
    /// document is still parsing, so remove stale pixels before AppKit gets a
    /// chance to stretch them. The opaque background remains stable until the
    /// new document supplies exact geometry.
    private func demoteWarmPreviewIfViewportChangedBeforeDocumentLoad() {
        guard pdfView.document == nil,
              !warmPreviewView.isHidden,
              let presentedWarmPreview,
              presentedWarmPreview.placement?.pageRect(
                  for: warmPreviewView.bounds.size
              ) == nil,
              let documentURL = warmPreviewView.documentURL,
              let frameSource = warmPreviewView.frameSource
        else { return }
        pendingWarmPreview = (
            presentedWarmPreview,
            documentURL,
            frameSource
        )
        self.presentedWarmPreview = nil
        latestPresentedTransitionFrameSource = nil
        warmPreviewView.showBackground(documentURL: documentURL)
        setLoading(true)
    }

    func clearWarmPreview() {
        warmPreviewTask?.cancel()
        warmPreviewTask = nil
        transitionCoverDismissalTask?.cancel()
        transitionCoverDismissalTask = nil
        warmPreviewKey = nil
        scheduledWarmPreviewPageIndex = nil
        onscreenPageDidDraw = false
        pendingWarmPreview = nil
        presentedWarmPreview = nil
        warmPreviewView.hide()
    }

    func cancelDocumentTransition() {
        setLoading(false)
        clearWarmPreview()
    }

    func displayTransitionCoverIfNeeded() {
        guard !warmPreviewView.isHidden else { return }
        alignTransitionCoverToCurrentPage()
        warmPreviewView.displayIfNeeded()
    }

    func alignTransitionCoverToCurrentPage() {
        guard !warmPreviewView.isHidden,
              warmPreviewView.image != nil,
              let document = pdfView.document,
              let page = pdfView.currentPage ?? document.page(at: 0)
        else {
            warmPreviewView.alignImage(to: nil)
            return
        }
        pdfView.layoutDocumentView()
        pdfView.layoutSubtreeIfNeeded()
        let pageRectInPDFView = pdfView.convert(
            page.bounds(for: .cropBox),
            from: page
        )
        let pageRectInPreview = warmPreviewView.convert(
            pageRectInPDFView,
            from: pdfView
        )
        guard pageRectInPreview.width.isFinite,
              pageRectInPreview.height.isFinite,
              pageRectInPreview.width > 0,
              pageRectInPreview.height > 0
        else { return }
        warmPreviewView.alignImage(to: pageRectInPreview)
        cacheExactPlacementIfNeeded(pageRect: pageRectInPreview)
    }

    private func cacheExactPlacementIfNeeded(pageRect: NSRect) {
        guard let warmPreviewKey,
              let presentedWarmPreview,
              let documentURL = warmPreviewView.documentURL
        else { return }
        let placement = PDFWarmPreviewPlacement(
            viewportSize: warmPreviewView.bounds.size,
            pageRect: pageRect
        )
        guard presentedWarmPreview.placement != placement else { return }
        let placedPreview = PDFWarmPreview(
            image: presentedWarmPreview.image,
            pageIndex: presentedWarmPreview.pageIndex,
            placement: placement
        )
        self.presentedWarmPreview = placedPreview
        let pixelCost = placedPreview.image.cgImage(
            forProposedRect: nil,
            context: nil,
            hints: nil
        ).map { $0.width * $0.height * 4 } ?? 1
        PDFWarmPreviewMemoryCache.shared.insert(
            placedPreview,
            for: warmPreviewKey,
            cost: pixelCost
        )
        guard !documentURL.path.hasPrefix(
            FileManager.default.temporaryDirectory.path
        ) else { return }
        Task {
            await PDFWarmPreviewDiskCache.shared.insert(
                placedPreview,
                for: warmPreviewKey
            )
        }
    }

    var currentPDFPageRectInTransitionCover: NSRect? {
        guard let document = pdfView.document,
              let page = pdfView.currentPage ?? document.page(at: 0)
        else { return nil }
        let pageRectInPDFView = pdfView.convert(
            page.bounds(for: .cropBox),
            from: page
        )
        return warmPreviewView.convert(pageRectInPDFView, from: pdfView)
    }

    func setLoading(_ loading: Bool) {
        isLoading = loading
        loadingIndicator.isHidden = !loading
        if loading {
            loadingIndicator.startAnimation(nil)
        } else {
            loadingIndicator.stopAnimation(nil)
        }
    }

    func setPDFBackgroundColor(_ color: NSColor) {
        pdfView.backgroundColor = color
        warmPreviewView.backgroundColor = color
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
        warmPreviewView.translatesAutoresizingMaskIntoConstraints = false
        thumbnailView.translatesAutoresizingMaskIntoConstraints = false
        loadingIndicator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(splitView)
        splitView.addArrangedSubview(mainPane)
        splitView.addArrangedSubview(thumbnailPane)

        mainPane.addSubview(pdfView)
        mainPane.addSubview(warmPreviewView)
        mainPane.addSubview(loadingIndicator)
        thumbnailPane.addSubview(thumbnailBackgroundView)
        thumbnailPane.addSubview(thumbnailView)

        thumbnailBackgroundView.material = .sidebar
        thumbnailBackgroundView.blendingMode = .withinWindow
        thumbnailBackgroundView.state = .active

        loadingIndicator.style = .bar
        loadingIndicator.controlSize = .small
        loadingIndicator.isIndeterminate = true
        loadingIndicator.isDisplayedWhenStopped = false
        loadingIndicator.isHidden = true
        warmPreviewView.isHidden = true
        warmPreviewView.onFirstDraw = { [weak self] documentURL, source, finishedAt in
            LibraryPDFLatencyTracker.shared.recordFirstPageDraw(
                documentURL: documentURL,
                source: source,
                finishedAt: finishedAt
            )
            self?.setLoading(false)
            guard let self, self.onscreenPageDidDraw else { return }
            self.scheduleTransitionCoverDismissal(for: documentURL)
        }

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

            warmPreviewView.leadingAnchor.constraint(equalTo: mainPane.leadingAnchor),
            warmPreviewView.trailingAnchor.constraint(equalTo: mainPane.trailingAnchor),
            warmPreviewView.topAnchor.constraint(equalTo: mainPane.topAnchor),
            warmPreviewView.bottomAnchor.constraint(equalTo: mainPane.bottomAnchor),

            loadingIndicator.centerXAnchor.constraint(equalTo: mainPane.centerXAnchor),
            loadingIndicator.centerYAnchor.constraint(equalTo: mainPane.centerYAnchor),
            loadingIndicator.widthAnchor.constraint(equalToConstant: 180),

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

    @objc
    private func pdfPageDidDraw(_ notification: Notification) {
        guard let documentURL = notification.userInfo?["documentURL"] as? URL,
              documentURL.standardizedFileURL == pdfView.document?.documentURL?.standardizedFileURL
        else { return }

        onscreenPageDidDraw = true
        scheduleWarmPreviewIfNeeded()
        guard !warmPreviewView.isHidden else {
            setLoading(false)
            LibraryPDFLatencyTracker.shared.recordStablePDFReveal(
                documentURL: documentURL
            )
            return
        }
        scheduleTransitionCoverDismissal(for: documentURL)
    }

    /// PDFKit renders a visible page as several independent tiles. Hiding the
    /// cover after the first tile recreates the white flash on complex PDFs,
    /// because the remaining native page tiles are still white. Debounce from
    /// the most recent completed draw and reveal only after the tile set has
    /// been quiet for several display frames.
    private func scheduleTransitionCoverDismissal(for documentURL: URL) {
        transitionCoverDismissalTask?.cancel()
        transitionCoverDismissalTask = Task { [weak self] in
            do {
                // PDFKit can pause between native tile draws even when an
                // exact cached page image is available. Keep that stable image
                // above PDFKit until the entire tile stream has been quiet;
                // using one invariant here prevents latency tuning from
                // reintroducing a white gap on complex papers.
                try await Task.sleep(for: .milliseconds(80))
            } catch {
                return
            }
            guard let self,
                  self.onscreenPageDidDraw,
                  self.warmPreviewView.documentURL == documentURL.standardizedFileURL,
                  self.pdfView.document?.documentURL?.standardizedFileURL
                    == documentURL.standardizedFileURL
            else { return }
            let revealedDarkTransition = !self.warmPreviewView.reportedCurrentImage
            self.warmPreviewView.hide()
            self.setLoading(false)
            if revealedDarkTransition {
                LibraryPDFLatencyTracker.shared.recordFirstPageDraw(
                    documentURL: documentURL,
                    source: .darkTransition,
                    finishedAt: .now
                )
            }
            LibraryPDFLatencyTracker.shared.recordStablePDFReveal(
                documentURL: documentURL
            )
            self.transitionCoverDismissalTask = nil
        }
    }

    private func scheduleWarmPreviewIfNeeded() {
        guard let warmPreviewKey,
              let document = pdfView.document,
              let page = pdfView.currentPage ?? document.page(at: 0)
        else { return }
        let pageIndex = document.index(for: page)
        guard pageIndex != NSNotFound,
              scheduledWarmPreviewPageIndex != pageIndex
        else { return }

        let pageBounds = page.bounds(for: .cropBox)
        guard pageBounds.width > 0,
              pageBounds.height > 0,
              let pageRect = currentPDFPageRectInTransitionCover
        else { return }
        scheduledWarmPreviewPageIndex = pageIndex
        let displayWidth = min(1_200, max(700, pdfView.bounds.width - 20))
        let displaySize = CGSize(
            width: displayWidth,
            height: displayWidth * pageBounds.height / pageBounds.width
        )
        let renderScale = min(2, window?.backingScaleFactor ?? 2)
        let placement = PDFWarmPreviewPlacement(
            viewportSize: warmPreviewView.bounds.size,
            pageRect: pageRect
        )
        let requiredPixelWidth = Int(
            ceil(displaySize.width * renderScale * 0.9)
        )
        if let cachedPreview = PDFWarmPreviewMemoryCache.shared.preview(
            for: warmPreviewKey
        ),
           cachedPreview.pageIndex == pageIndex,
           cachedPreview.placement?.matches(
               viewportSize: warmPreviewView.bounds.size,
               pageRect: pageRect
           ) == true,
           let cachedImage = cachedPreview.image.cgImage(
               forProposedRect: nil,
               context: nil,
               hints: nil
           ),
           cachedImage.width >= requiredPixelWidth {
            return
        }
        let pixelCost = max(
            1,
            Int(ceil(displaySize.width * renderScale))
                * Int(ceil(displaySize.height * renderScale))
                * 4
        )
        let request = PDFWarmPreviewRequest(
            page: page,
            displaySize: displaySize,
            renderScale: renderScale,
            cacheKey: warmPreviewKey,
            pixelCost: pixelCost,
            pageIndex: pageIndex,
            placement: placement,
            persistToDisk: document.documentURL.map {
                !$0.path.hasPrefix(
                    FileManager.default.temporaryDirectory.path
                )
            } ?? false
        )
        warmPreviewTask = Task {
            await PDFWarmPreviewRenderQueue.shared.prepare(request)
        }
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
private final class PDFThumbnailStackView: NSStackView {
    override var isFlipped: Bool { true }
}

@MainActor
final class PDFThumbnailSidebarView: NSScrollView {
    static let sidebarHorizontalMargin: CGFloat = 64
    static let initialSynchronousItemCount = 1
    static let incrementalItemBatchSize = 4
    static let incrementalItemDelay: TimeInterval = 0.01

    weak var pdfView: PDFView? {
        didSet {
            guard oldValue !== pdfView else { return }
            updatePageChangeObserver()
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

    private let stackView = PDFThumbnailStackView()
    private var lastDisplayedThumbnailWidth: CGFloat = 0
    private var lastRenderedThumbnailWidth: CGFloat = 0
    private weak var thumbnailDocument: PDFDocument?
    private var thumbnailCacheNamespace = ""
    private var thumbnailItemLoadTask: Task<Void, Never>?
    private var nextDeferredItemIndex: Int?
    private var nextDeferredRenderIndex: Int?

    var isDocumentStackFlipped: Bool { stackView.isFlipped }

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
            thumbnailCacheNamespace = ""
            lastDisplayedThumbnailWidth = 0
            lastRenderedThumbnailWidth = 0
            return
        }
        let thumbnailWidth = currentThumbnailWidth()
        lastDisplayedThumbnailWidth = thumbnailWidth
        lastRenderedThumbnailWidth = thumbnailWidth
        thumbnailDocument = document
        if let documentURL = document.documentURL {
            thumbnailCacheNamespace = PDFFileCacheDescriptor(url: documentURL).identity
        } else {
            thumbnailCacheNamespace = "memory:\(ObjectIdentifier(document).hashValue)"
        }
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
                thumbnailSize: thumbnailDisplaySize(for: page, width: thumbnailWidth),
                cacheNamespace: thumbnailCacheNamespace
            )
            item.target = self
            item.action = #selector(selectThumbnail(_:))
            item.isSelected = page === selectedPage
            thumbnailItems.append(item)
            stackView.addArrangedSubview(item)
            let restoredCachedThumbnail = item.applyCachedThumbnailIfAvailable(
                renderScale: renderScale
            )
            if scheduleFirstRender && index == 0 && !restoredCachedThumbnail {
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
    private let cacheNamespace: String
    private var widthConstraint: NSLayoutConstraint?
    private var heightConstraint: NSLayoutConstraint?
    private var imageWidthConstraint: NSLayoutConstraint?
    private var imageHeightConstraint: NSLayoutConstraint?
    private var renderGeneration = 0
    private var renderTask: Task<Void, Never>?

    init(
        page: PDFPage,
        pageIndex: Int,
        thumbnailSize: CGSize,
        cacheNamespace: String
    ) {
        self.page = page
        self.pageIndex = pageIndex
        self.thumbnailSize = thumbnailSize
        self.cacheNamespace = cacheNamespace
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

        let request = makeRenderRequest(renderScale: renderScale)
        if let cachedImage = PDFThumbnailMemoryCache.shared.image(for: request.cacheKey) {
            imageView.image = cachedImage
            hasRenderedThumbnail = true
            completion?()
            return
        }
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

    @discardableResult
    func applyCachedThumbnailIfAvailable(renderScale: CGFloat) -> Bool {
        let request = makeRenderRequest(renderScale: renderScale)
        guard let cachedImage = PDFThumbnailMemoryCache.shared.image(for: request.cacheKey) else {
            return false
        }
        imageView.image = cachedImage
        hasRenderedThumbnail = true
        return true
    }

    private func makeRenderRequest(renderScale: CGFloat) -> PDFThumbnailRenderRequest {
        let pixelWidth = max(1, Int(ceil(thumbnailSize.width * renderScale)))
        let pixelHeight = max(1, Int(ceil(thumbnailSize.height * renderScale)))
        let cacheWidth = Self.cacheDimension(for: pixelWidth)
        let cacheHeight = Self.cacheDimension(for: pixelHeight)
        let cacheKey = [
            cacheNamespace,
            String(reflecting: type(of: page)),
            String(pageIndex),
            "\(cacheWidth)x\(cacheHeight)"
        ].joined(separator: "|")
        return PDFThumbnailRenderRequest(
            page: page,
            displaySize: thumbnailSize,
            renderScale: renderScale,
            cacheKey: cacheKey,
            pixelCost: pixelWidth * pixelHeight * 4
        )
    }

    /// Divider layout can vary by a fraction of a point between otherwise
    /// identical visits. Eight-pixel buckets avoid discarding a perfectly
    /// sharp cached thumbnail because of a one-pixel rounding difference.
    private static func cacheDimension(for pixels: Int) -> Int {
        let bucketSize = 8
        return max(bucketSize, ((pixels + bucketSize / 2) / bucketSize) * bucketSize)
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
    let cacheKey: String
    let pixelCost: Int

    init(
        page: PDFPage,
        displaySize: CGSize,
        renderScale: CGFloat,
        cacheKey: String,
        pixelCost: Int
    ) {
        self.page = page
        self.displaySize = displaySize
        self.renderScale = renderScale
        self.cacheKey = cacheKey
        self.pixelCost = pixelCost
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
        if let cached = PDFThumbnailMemoryCache.shared.image(for: request.cacheKey) {
            return PDFThumbnailRenderResult(image: cached)
        }
        guard !Task.isCancelled else { return nil }
        let image = PDFThumbnailRenderingContext.perform {
            PDFThumbnailRasterizer.thumbnail(
                page: request.page,
                displaySize: request.displaySize,
                box: .cropBox,
                renderScale: request.renderScale
            ) ?? request.page.thumbnail(of: request.displaySize, for: .cropBox)
        }
        guard !Task.isCancelled else { return nil }
        PDFThumbnailMemoryCache.shared.insert(
            image,
            for: request.cacheKey,
            cost: request.pixelCost
        )
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
        PDFThumbnailRenderingContext.perform {
            page.draw(with: box, to: context)
        }
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
        PDFPageDrawReporter.report(self)
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
