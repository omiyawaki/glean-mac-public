import SwiftUI
import WebKit

/// WKWebView wrapped for SwiftUI. Backed by the default persistent
/// website data store, so cookies and cache accumulate across selections
/// and app launches — once you clear a CloudFlare check on a publisher's
/// site, the cookie persists and you don't get re-prompted next time.
/// Custom user-agent matches Safari on macOS Tahoe so bot-detection
/// services don't fingerprint the WebView as third-party automation.
struct WebViewer: NSViewRepresentable {
    let url: URL?
    var onPDFDownloaded: (URL) -> Void = { _ in }
    var onDownloadFailed: (String) -> Void = { _ in }

    /// User-agent string that matches a recent Safari on macOS so
    /// CloudFlare etc. don't flag the request as automation. Suffix
    /// (".../Safari/...") is what most bot detectors key on.
    private static let safariUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 26_0) " +
        "AppleWebKit/618.4.11 (KHTML, like Gecko) " +
        "Version/19.0 Safari/618.4.11"

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()  // explicit; the default is persistent
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        Self.installDarkReader(in: config.userContentController)

        let view = WKWebView(frame: .zero, configuration: config)
        view.navigationDelegate = context.coordinator
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        view.customUserAgent = Self.safariUserAgent
        // Register web.* actions on every build, not just DEBUG. The
        // Release builds need these too; the DEBUG-only HTTP server
        // is just one of several possible in-process callers.
        registerIntrospection(for: view)
        return view
    }

    /// Inject Dark Reader as a per-frame user script. The bundled
    /// `darkreader.js` defines a `DarkReader` global; the bootstrap
    /// after it calls `DarkReader.enable(...)` with a Noir-ish theme
    /// (slightly reduced brightness, a touch of sepia to soften the
    /// black so long PDF-adjacent reading sessions are easier on the
    /// eyes). Runs at document-end so the DOM is ready, and on every
    /// frame so publisher iframe-embedded readers also flip.
    ///
    /// We can't load Noir directly (closed-source Safari extension,
    /// only loadable into Safari proper). Dark Reader (MIT) is the
    /// canonical open-source equivalent and behaves indistinguishably
    /// on the publisher pages we care about.
    private static func installDarkReader(in controller: WKUserContentController) {
        guard let url = Bundle.module.url(forResource: "darkreader", withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        controller.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
        let bootstrap = """
        (() => {
          if (typeof DarkReader === 'undefined') return;
          try {
            DarkReader.setFetchMethod(window.fetch);
            DarkReader.enable({
              brightness: 100,
              contrast: 90,
              sepia: 10
            });
          } catch (_) {}
        })();
        """
        controller.addUserScript(WKUserScript(
            source: bootstrap,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: false
        ))
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        context.coordinator.parent = self
        guard let url else { return }
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKDownloadDelegate {
        var parent: WebViewer
        private var destinationsByDownload = [ObjectIdentifier: URL]()
        init(_ parent: WebViewer) {
            self.parent = parent
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void
        ) {
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationResponse: WKNavigationResponse,
            decisionHandler: @escaping @MainActor @Sendable (WKNavigationResponsePolicy) -> Void
        ) {
            let response = navigationResponse.response
            if WebPDFDownloadPolicy.isPDF(
                mimeType: response.mimeType,
                url: response.url
            ) {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(
            _ webView: WKWebView,
            navigationAction: WKNavigationAction,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func webView(
            _ webView: WKWebView,
            navigationResponse: WKNavigationResponse,
            didBecome download: WKDownload
        ) {
            download.delegate = self
        }

        func download(
            _ download: WKDownload,
            decideDestinationUsing response: URLResponse,
            suggestedFilename: String,
            completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
        ) {
            let destination = WebPDFDownloadPolicy.destinationURL(
                suggestedFilename: suggestedFilename,
                responseURL: response.url
            )
            destinationsByDownload[ObjectIdentifier(download)] = destination
            completionHandler(destination)
        }

        func downloadDidFinish(_ download: WKDownload) {
            let key = ObjectIdentifier(download)
            guard let destination = destinationsByDownload.removeValue(forKey: key) else {
                return
            }
            parent.onPDFDownloaded(destination)
        }

        func download(
            _ download: WKDownload,
            didFailWithError error: Error,
            resumeData: Data?
        ) {
            destinationsByDownload.removeValue(forKey: ObjectIdentifier(download))
            parent.onDownloadFailed(error.localizedDescription)
        }
    }

    @MainActor
    private func registerIntrospection(for webView: WKWebView) {
        let registry = IntrospectionRegistry.shared
        let probe = WebPDFDebugProbe()
        registry.registerState(key: "web.url") {
            webView.url?.absoluteString ?? "<none>"
        }
        registry.registerState(key: "web.title") {
            webView.title ?? "<none>"
        }
        registry.registerState(key: "web.pdfProbe") {
            probe.lastResult
        }
        registry.registerAction(id: "web.navigate") { @MainActor (payload: [String: Any]?) in
            guard let rawURL = payload?["url"] as? String,
                  let url = URL(string: rawURL) else {
                return
            }
            webView.load(URLRequest(url: url))
        }
        registry.registerAction(id: "web.probePDFLinks") { @MainActor in
            probe.lastResult = await evaluatePDFDebugScript(pdfProbeScript, in: webView)
        }
        registry.registerAction(id: "web.clickPDFLink") { @MainActor in
            probe.lastResult = await evaluatePDFDebugScript(pdfClickScript, in: webView)
        }
    }

    @MainActor
    private final class WebPDFDebugProbe {
        var lastResult = "<not run>"
    }

    @MainActor
    private func evaluatePDFDebugScript(_ script: String, in webView: WKWebView) async -> String {
        do {
            let value = try await webView.evaluateJavaScript(script)
            guard let value else { return "<nil>" }
            if let string = value as? String {
                return string
            }
            return String(describing: value)
        } catch {
            return "error: \(error.localizedDescription)"
        }
    }

    private var pdfProbeScript: String {
        """
        (() => {
          const norm = value => (value || "").replace(/\\s+/g, " ").trim();
          const nodes = Array.from(document.querySelectorAll('a, button, [role="button"]'));
          const candidates = nodes.map((element, index) => {
            const text = norm([
              element.innerText,
              element.textContent,
              element.getAttribute("aria-label"),
              element.getAttribute("title")
            ].filter(Boolean).join(" "));
            const href = element.href || element.getAttribute("href") || "";
            const haystack = `${text} ${href}`.toLowerCase();
            let score = 0;
            if (text.toLowerCase().includes("download pdf")) score += 100;
            if (text.toLowerCase() === "pdf") score += 80;
            if (text.toLowerCase().includes("pdf")) score += 30;
            if (href.includes("/doi/epdf/")) score += 80;
            if (href.includes("/doi/pdf/")) score += 80;
            if (haystack.includes("pdf")) score += 10;
            return {
              index,
              tag: element.tagName.toLowerCase(),
              text: text.slice(0, 160),
              href,
              visible: !!(element.offsetWidth || element.offsetHeight || element.getClientRects().length),
              score
            };
          }).filter(candidate => candidate.score > 0)
            .sort((a, b) => b.score - a.score || a.index - b.index)
            .slice(0, 12);
          return JSON.stringify(candidates);
        })()
        """
    }

    private var pdfClickScript: String {
        """
        (() => {
          const norm = value => (value || "").replace(/\\s+/g, " ").trim();
          const nodes = Array.from(document.querySelectorAll('a, button, [role="button"]'));
          const scored = nodes.map((element, index) => {
            const text = norm([
              element.innerText,
              element.textContent,
              element.getAttribute("aria-label"),
              element.getAttribute("title")
            ].filter(Boolean).join(" "));
            const href = element.href || element.getAttribute("href") || "";
            const haystack = `${text} ${href}`.toLowerCase();
            let score = 0;
            if (text.toLowerCase().includes("download pdf")) score += 100;
            if (text.toLowerCase() === "pdf") score += 80;
            if (text.toLowerCase().includes("pdf")) score += 30;
            if (href.includes("/doi/epdf/")) score += 80;
            if (href.includes("/doi/pdf/")) score += 80;
            if (haystack.includes("pdf")) score += 10;
            return { element, index, text, href, score };
          }).filter(candidate => candidate.score > 0)
            .sort((a, b) => b.score - a.score || a.index - b.index);

          const hit = scored[0];
          if (!hit) {
            return JSON.stringify({ clicked: false, reason: "no PDF candidates" });
          }
          hit.element.scrollIntoView({ block: "center", inline: "center" });
          // Many publishers (ScienceDirect, IOPscience, …) mark their
          // "View PDF" anchor target="_blank". WKWebView blocks the
          // popup by default, so the click looks like it did nothing.
          // Strip the target attribute first so the navigation happens
          // in the main frame and our response-download path can fire.
          if (hit.element.tagName.toLowerCase() === "a") {
            hit.element.removeAttribute("target");
          }
          hit.element.click();
          return JSON.stringify({
            clicked: true,
            tag: hit.element.tagName.toLowerCase(),
            text: hit.text.slice(0, 160),
            href: hit.href,
            score: hit.score
          });
        })()
        """
    }
}
