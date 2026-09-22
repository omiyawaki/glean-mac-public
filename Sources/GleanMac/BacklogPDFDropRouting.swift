import Foundation

enum BacklogPDFDropRouting {
    static func pdfURLs(from urls: [URL]) -> [URL] {
        urls.filter { $0.pathExtension.lowercased() == "pdf" }
    }

    static func forceAttachCitekey(_ citekey: String?) -> String? {
        guard let citekey = citekey?.trimmingCharacters(in: .whitespacesAndNewlines),
              !citekey.isEmpty
        else { return nil }
        return citekey
    }

    static func forceAttachCitekey(for entry: BacklogEntry?) -> String? {
        forceAttachCitekey(entry?.citekey)
    }

    static func forceAttachCitekey(for entry: LibraryEntry?) -> String? {
        forceAttachCitekey(entry?.citekey)
    }

    static func forceAttachCitekey(for record: LibraryRecord?) -> String? {
        forceAttachCitekey(record?.citekey)
    }

    @MainActor
    @discardableResult
    static func enqueueForceAttach(
        urls: [URL],
        citekey: String?,
        actionQueue: ActionQueueStore,
        offlineCoordinator: OfflineIntakeCoordinator,
        syncPendingOperations: @escaping () async -> Void,
        onPlaced: @escaping @MainActor () async -> Void = {}
    ) -> Bool {
        guard let citekey = forceAttachCitekey(citekey) else { return false }
        let pdfs = pdfURLs(from: urls)
        for url in pdfs {
            actionQueue.enqueue(
                title: "Attach PDF",
                detail: url.lastPathComponent,
                systemImage: "doc.richtext",
                operation: {
                    _ = try await offlineCoordinator.placeAttachmentInICloud(
                        url,
                        citekey: citekey
                    )
                    PDFSourceCleaner.system.trashSourcePDF(url)
                    await syncPendingOperations()
                    await onPlaced()
                },
                forceAttach: { altCitekey in
                    _ = try await offlineCoordinator.placeAttachmentInICloud(
                        url,
                        citekey: altCitekey
                    )
                    PDFSourceCleaner.system.trashSourcePDF(url)
                    await syncPendingOperations()
                    await onPlaced()
                }
            )
        }
        return !pdfs.isEmpty
    }
}
