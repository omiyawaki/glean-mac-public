import Foundation

enum BacklogPDFManualFetchPresentation {
    static let menuTitle = "Try Fetching PDF"
    static let toolbarTitle = "Find PDF"
    static let systemImage = "arrow.down.doc"

    static func isAvailable(for entry: BacklogEntry?) -> Bool {
        guard let entry else { return false }
        return !entry.doi.isEmpty
    }
}

@MainActor
struct BacklogPDFManualFetcher {
    typealias ActionRunner = @MainActor (_ id: String, _ payload: [String: Any]?) async -> Bool
    typealias Sleeper = @MainActor (_ duration: Duration) async -> Void

    var runAction: ActionRunner = { id, payload in
        await IntrospectionRegistry.shared.runAction(id: id, payload: payload)
    }
    var sleep: Sleeper = { duration in
        try? await Task.sleep(for: duration)
    }

    var pageSettleDelay: Duration = .seconds(10)
    var pdfSettleDelay: Duration = .seconds(10)

    func fetchPDF(for entry: BacklogEntry, isAlreadySelected: Bool = false) async {
        guard !entry.doi.isEmpty else { return }

        if !isAlreadySelected {
            _ = await runAction("backlog.selectByID", ["id": entry.id])
            await sleep(pageSettleDelay)
        }

        _ = await runAction("web.clickPDFLink", nil)
        await sleep(pdfSettleDelay)
    }
}
