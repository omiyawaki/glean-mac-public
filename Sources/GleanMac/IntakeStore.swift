import Foundation
import Observation
import SwiftUI
import os

private let log = Logger(subsystem: "com.miyawaki.glean-mac", category: "intake-store")

/// Generic store backing every list view that fetches a paged
/// `{count, entries}`-shaped payload. The four concrete stores
/// (Backlog, Maybe Review, Author Proposals, Library) only differ
/// in their endpoint URL and entry type — everything else (load
/// state machine, spinner floor, smooth row diffing, last-refresh
/// timestamp) is identical and lives here.
@MainActor
@Observable
final class IntakeStore<Entry: Identifiable & Codable & Sendable, Response: Codable & Sendable>
where Entry.ID: Hashable {
    var entries: [Entry] = []
    var count: Int = 0
    var isLoading: Bool = false
    var lastError: String? = nil
    var hasLoadedOnce: Bool = false
    var lastRefreshedAt: Date? = nil

    private let endpoint: URL
    private let extract: (Response) -> (Int, [Entry])
    private let timeoutInterval: TimeInterval
    private let minSpinnerDuration: Duration
    private let loadCachedResponse: (() async throws -> Response?)?
    private let saveResponse: ((Response) async throws -> Void)?
    private var optimisticallyRemovedIDs: Set<Entry.ID> = []
    private var responseETag: String?

    init(endpoint: URL,
         timeoutInterval: TimeInterval = 8,
         minSpinnerDuration: Duration = .milliseconds(700),
         loadCachedResponse: (() async throws -> Response?)? = nil,
         saveResponse: ((Response) async throws -> Void)? = nil,
         extract: @escaping (Response) -> (Int, [Entry])) {
        self.endpoint = endpoint
        self.timeoutInterval = timeoutInterval
        self.minSpinnerDuration = minSpinnerDuration
        self.loadCachedResponse = loadCachedResponse
        self.saveResponse = saveResponse
        self.extract = extract
    }

    /// Fetch and apply. When `silent` is true, the spinner is suppressed
    /// (used by SSE-driven refreshes); the very first load still shows
    /// it because otherwise the screen would be blank.
    func load(silent: Bool = false) async {
        let showSpinner = !silent || !hasLoadedOnce
        if showSpinner { isLoading = true }
        let started = ContinuousClock.now
        log.debug("load start url=\(self.endpoint.absoluteString, privacy: .public) silent=\(silent, privacy: .public)")

        if !hasLoadedOnce, let loadCachedResponse {
            do {
                if let cached = try await loadCachedResponse() {
                    apply(cached, animated: false)
                }
            } catch {
                log.warning("cache load failed url=\(self.endpoint.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            }
        }

        do {
            var request = URLRequest(url: endpoint)
            request.timeoutInterval = timeoutInterval
            if let responseETag {
                request.setValue(responseETag,
                                 forHTTPHeaderField: "If-None-Match")
            }
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                lastError = "Invalid response"
                if showSpinner {
                    await holdSpinner(since: started)
                    isLoading = false
                }
                return
            }
            if http.statusCode == 304 {
                lastError = nil
                lastRefreshedAt = Date()
                if showSpinner {
                    await holdSpinner(since: started)
                    isLoading = false
                }
                return
            }
            guard http.statusCode == 200 else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? -1
                lastError = "HTTP \(code)"
                log.warning("load http_error url=\(self.endpoint.absoluteString, privacy: .public) status=\(code, privacy: .public)")
                if showSpinner {
                    await holdSpinner(since: started)
                    isLoading = false
                }
                return
            }
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let payload = try decoder.decode(Response.self, from: data)
            apply(payload, animated: true)
            lastError = nil
            responseETag = http.value(forHTTPHeaderField: "ETag")
            if let saveResponse {
                try? await saveResponse(payload)
            }
            let ms = (ContinuousClock.now - started) / .milliseconds(1)
            log.debug("load ok url=\(self.endpoint.absoluteString, privacy: .public) entries=\(self.count, privacy: .public) ms=\(ms, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("load decode_or_io_error url=\(self.endpoint.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
        }

        if showSpinner {
            await holdSpinner(since: started)
            isLoading = false
        }
    }

    private func apply(_ payload: Response, animated: Bool) {
        let (newCount, newEntries) = extract(payload)
        let filteredEntries = newEntries.filter {
            !optimisticallyRemovedIDs.contains($0.id)
        }
        let hiddenCount = newEntries.count - filteredEntries.count
        let update = {
            self.entries = filteredEntries
            self.count = max(0, newCount - hiddenCount)
            self.hasLoadedOnce = true
            self.lastRefreshedAt = Date()
        }
        if animated {
            withAnimation(.smooth) { update() }
        } else {
            update()
        }
    }

    func optimisticallyRemove(id: Entry.ID) {
        optimisticallyRemovedIDs.insert(id)
        guard entries.contains(where: { $0.id == id }) else { return }
        withAnimation(.smooth) {
            entries.removeAll { $0.id == id }
            count = max(0, count - 1)
            lastRefreshedAt = Date()
        }
    }

    func releaseOptimisticRemoval(id: Entry.ID) {
        optimisticallyRemovedIDs.remove(id)
    }

    private func holdSpinner(since started: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - started
        if elapsed < minSpinnerDuration {
            try? await Task.sleep(for: minSpinnerDuration - elapsed)
        }
    }
}

// MARK: - Concrete factories

@MainActor
enum Stores {
    private static let intakeBase = URL(string: "http://backend.example.com:8765")!
    private static let libraryBase = URL(string: "http://backend.example.com:8766")!

    static func backlog() -> IntakeStore<BacklogEntry, BacklogResponse> {
        IntakeStore(
            endpoint: intakeBase.appendingPathComponent("/api/backlog"),
            extract: { ($0.count, $0.entries) }
        )
    }

    static func review() -> IntakeStore<ReviewEntry, ReviewResponse> {
        IntakeStore(
            endpoint: intakeBase.appendingPathComponent("/api/review-queue"),
            extract: { ($0.count, $0.entries) }
        )
    }

    static func author() -> IntakeStore<AuthorProposal, AuthorProposalsResponse> {
        IntakeStore(
            endpoint: intakeBase.appendingPathComponent("/api/author-proposals"),
            extract: { ($0.count, $0.entries) }
        )
    }

    static func library(
        snapshotCache: LibrarySnapshotCache = .default,
        localIndexReader: LocalLibraryIndexReader? = .default
    ) -> IntakeStore<LibraryEntry, LibraryResponse> {
        IntakeStore(
            endpoint: libraryBase.appendingPathComponent("/api/papers"),
            timeoutInterval: 15,
            minSpinnerDuration: .milliseconds(0),
            loadCachedResponse: {
                if let snapshot = try await snapshotCache.load() {
                    return snapshot
                }
                return try await localIndexReader?.load()
            },
            saveResponse: { try await snapshotCache.save($0) },
            extract: { ($0.count, $0.entries) }
        )
    }
}

typealias BacklogStore = IntakeStore<BacklogEntry, BacklogResponse>
typealias ReviewStore = IntakeStore<ReviewEntry, ReviewResponse>
typealias AuthorStore = IntakeStore<AuthorProposal, AuthorProposalsResponse>
typealias LibraryStore = IntakeStore<LibraryEntry, LibraryResponse>
