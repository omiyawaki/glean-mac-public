import Foundation

@MainActor
struct OfflineIntakeCoordinator {
    let operationStore: PendingOperationStore
    let pdfStager: PendingPDFStager
    let signalExtractor: LocalPaperSignalExtractor
    let attachmentPlacer: ICloudAttachmentPlacer

    init(operationStore: PendingOperationStore,
         pdfStager: PendingPDFStager = .default,
         signalExtractor: LocalPaperSignalExtractor = .default,
         attachmentPlacer: ICloudAttachmentPlacer = .system) {
        self.operationStore = operationStore
        self.pdfStager = pdfStager
        self.signalExtractor = signalExtractor
        self.attachmentPlacer = attachmentPlacer
    }

    @discardableResult
    func queueReviewAdd(doi: String) async throws -> PendingOperation {
        try await operationStore.enqueue(.reviewAdd(doi: doi))
    }

    @discardableResult
    func queueReviewSkip(doi: String) async throws -> PendingOperation {
        try await operationStore.enqueue(.reviewSkip(doi: doi))
    }

    @discardableResult
    func queueAuthorFollow(author: String) async throws -> PendingOperation {
        try await operationStore.enqueue(.authorFollow(author: author))
    }

    @discardableResult
    func queueAuthorDismiss(author: String) async throws -> PendingOperation {
        try await operationStore.enqueue(.authorDismiss(author: author))
    }

    func placeAttachmentInICloud(_ source: URL, citekey: String) async throws -> URL {
        let staged = try await pdfStager.stage(source)
        defer { try? FileManager.default.removeItem(at: staged) }
        return try await attachmentPlacer.place(stagedPDF: staged, citekey: citekey)
    }

    @discardableResult
    func queueAttachPDF(_ source: URL,
                        citekey: String? = nil) async throws -> PendingOperation {
        let staged = try await pdfStager.stage(source)
        return try await operationStore.enqueue(
            .attachPDF(stagedFilePath: staged.path, citekey: citekey)
        )
    }

    @discardableResult
    func queueAddPaper(input: String,
                       pdf: URL? = nil) async throws -> PendingOperation {
        var normalizedInput = input.trimmingCharacters(in: .whitespacesAndNewlines)
        let stagedPDFPath: String?
        if let pdf {
            let staged = try await pdfStager.stage(pdf)
            stagedPDFPath = staged.path
            if normalizedInput.isEmpty,
               let candidate = try await signalExtractor.doiCandidates(in: staged).first {
                normalizedInput = candidate
            }
        } else {
            stagedPDFPath = nil
        }
        return try await operationStore.enqueue(
            .addPaper(input: normalizedInput, stagedPDFPath: stagedPDFPath)
        )
    }

    @discardableResult
    func queueDeletePaper(citekey: String,
                          doi: String? = nil,
                          title: String? = nil) async throws -> PendingOperation {
        try await operationStore.enqueue(
            .deletePaper(
                citekey: citekey.trimmingCharacters(in: .whitespacesAndNewlines),
                doi: doi?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                title: title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            )
        )
    }
}
