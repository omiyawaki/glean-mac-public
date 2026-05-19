import Foundation

@MainActor
struct OfflineIntakeCoordinator {
    let operationStore: PendingOperationStore
    let pdfStager: PendingPDFStager

    init(operationStore: PendingOperationStore,
         pdfStager: PendingPDFStager = .default) {
        self.operationStore = operationStore
        self.pdfStager = pdfStager
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
        let stagedPDFPath: String?
        if let pdf {
            stagedPDFPath = try await pdfStager.stage(pdf).path
        } else {
            stagedPDFPath = nil
        }
        return try await operationStore.enqueue(
            .addPaper(input: input, stagedPDFPath: stagedPDFPath)
        )
    }
}
