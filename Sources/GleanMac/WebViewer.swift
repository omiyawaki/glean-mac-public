import SwiftUI
import WebKit

/// WKWebView wrapped for SwiftUI. Backed by a single shared process pool
/// and the default (persistent) website data store, so cookies and cache
/// accumulate across selections and app launches — once you clear a
/// CloudFlare check on a publisher's site, the cookie persists and you
/// don't get re-prompted next time. Custom user-agent matches Safari on
/// macOS Tahoe so bot-detection services don't fingerprint the WebView
/// as third-party automation.
struct WebViewer: NSViewRepresentable {
    let url: URL?

    /// Shared across every WebViewer instance for the lifetime of the
    /// app. Sharing the process pool keeps the same networking context
    /// across views, so CloudFlare and similar services see a stable
    /// client identity rather than a fresh process each selection.
    @MainActor
    private static let processPool = WKProcessPool()

    /// User-agent string that matches a recent Safari on macOS so
    /// CloudFlare etc. don't flag the request as automation. Suffix
    /// (".../Safari/...") is what most bot detectors key on.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 26_0) " +
        "AppleWebKit/618.4.11 (KHTML, like Gecko) " +
        "Version/19.0 Safari/618.4.11"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.processPool = Self.processPool
        config.websiteDataStore = .default()  // explicit; the default is persistent
        config.defaultWebpagePreferences.allowsContentJavaScript = true

        let view = WKWebView(frame: .zero, configuration: config)
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.customUserAgent = Self.safariUserAgent
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let url else { return }
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
