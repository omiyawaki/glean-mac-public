import SwiftUI
import PDFKit

/// PDFKit's PDFView wrapped for SwiftUI. Single-page-continuous, autoscales
/// to width — matches Preview.app's default reading layout. The view diffs
/// the document URL on update so swapping rows doesn't tear down the view.
struct PDFViewer: NSViewRepresentable {
    let url: URL?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.backgroundColor = .clear
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if let url {
            if nsView.document?.documentURL != url {
                nsView.document = PDFDocument(url: url)
            }
        } else {
            nsView.document = nil
        }
    }
}
