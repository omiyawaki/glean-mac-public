import SwiftUI
import WebKit

/// WKWebView wrapped for SwiftUI. Loads a URL on each update if it
/// changed; otherwise leaves the view alone (so user navigation isn't
/// reset on every state tick).
struct WebViewer: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> WKWebView {
        let view = WKWebView()
        view.allowsBackForwardNavigationGestures = true
        view.allowsMagnification = true
        return view
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {
        guard let url else { return }
        if nsView.url != url {
            nsView.load(URLRequest(url: url))
        }
    }
}
