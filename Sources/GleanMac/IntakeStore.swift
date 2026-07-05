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
///
/// Optimistic removals (used by Maybe Review and Author Proposals for
/// instant "Add/Skip/Follow/Dismiss" feedback) are automatically
/// released ("self-healing") when a subsequent server payload no
/// longer contains the ID. This eliminates timing races between
/// local release and the next event-driven or manual load. Callers
/// must still explicitly clear the protection (and reload) on error
/// paths so that failed mutations do not leave rows permanently hidden.
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
    private let automaticRetryDelay: Duration?
    private let maxAutomaticRetryAttempts: Int
    private var optimisticallyRemovedIDs: Set<Entry.ID> = []
    private var responseETag: String?
    private var automaticRetryTask: Task<Void, Never>?
    private var automaticRetryAttempts = 0
    private var isLoadInFlight = false
    private var loadWaiters: [CheckedContinuation<Void, Never>] = []

    init(endpoint: URL,
         timeoutInterval: TimeInterval = 8,
         minSpinnerDuration: Duration = .milliseconds(700),
         loadCachedResponse: (() async throws -> Response?)? = nil,
         saveResponse: ((Response) async throws -> Void)? = nil,
         automaticRetryDelay: Duration? = nil,
         maxAutomaticRetryAttempts: Int = 0,
         extract: @escaping (Response) -> (Int, [Entry])) {
        self.endpoint = endpoint
        self.timeoutInterval = timeoutInterval
        self.minSpinnerDuration = minSpinnerDuration
        self.loadCachedResponse = loadCachedResponse
        self.saveResponse = saveResponse
        self.automaticRetryDelay = automaticRetryDelay
        self.maxAutomaticRetryAttempts = max(0, maxAutomaticRetryAttempts)
        self.extract = extract
    }

    /// Fetch and apply. When `silent` is true, the spinner is suppressed
    /// (used by SSE-driven refreshes); the very first load still shows
    /// it because otherwise the screen would be blank.
    func load(silent: Bool = false) async {
        if isLoadInFlight {
            await waitForCurrentLoad()
            return
        }
        isLoadInFlight = true
        defer {
            isLoadInFlight = false
            resumeLoadWaiters()
        }

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
            request.cachePolicy = .reloadIgnoringLocalCacheData
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
                resetAutomaticRetry()
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
                scheduleAutomaticRetryIfNeeded()
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
            resetAutomaticRetry()
            if let saveResponse {
                try? await saveResponse(payload)
            }
            let ms = (ContinuousClock.now - started) / .milliseconds(1)
            log.debug("load ok url=\(self.endpoint.absoluteString, privacy: .public) entries=\(self.count, privacy: .public) ms=\(ms, privacy: .public)")
        } catch {
            lastError = error.localizedDescription
            log.error("load decode_or_io_error url=\(self.endpoint.absoluteString, privacy: .public) error=\(error.localizedDescription, privacy: .public)")
            scheduleAutomaticRetryIfNeeded()
        }

        if showSpinner {
            await holdSpinner(since: started)
            isLoading = false
        }
    }

    private func apply(_ payload: Response, animated: Bool) {
        let (newCount, newEntries) = extract(payload)

        // Self-healing optimistic removal: if the authoritative server
        // payload no longer lists an ID we were locally hiding, the
        // mutation has landed (or the entry was otherwise removed, e.g.
        // by reconcile). Drop it from the protection set so future
        // loads are not affected. This is the key part of the root fix
        // for the "flash reappear" race.
        let serverIDs = Set(newEntries.map(\.id))
        optimisticallyRemovedIDs = optimisticallyRemovedIDs.intersection(serverIDs)

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

    /// Immediately hide a row locally while a mutation (add/skip/follow/dismiss)
    /// is in flight. The ID is protected across *all* subsequent loads (silent
    /// or not) until either:
    ///   - the server payload no longer contains it (auto-pruned in apply), or
    ///   - the caller explicitly calls releaseOptimisticRemoval (primarily used
    ///     on error paths to restore visibility).
    func optimisticallyRemove(id: Entry.ID) {
        optimisticallyRemovedIDs.insert(id)
        guard entries.contains(where: { $0.id == id }) else { return }
        withAnimation(.smooth) {
            entries.removeAll { $0.id == id }
            count = max(0, count - 1)
            lastRefreshedAt = Date()
        }
    }

    /// Explicitly stop protecting an ID. Primarily called on error paths
    /// so that a failed mutation does not leave the row permanently hidden.
    /// On success paths the auto-pruning in apply() is usually sufficient.
    func releaseOptimisticRemoval(id: Entry.ID) {
        optimisticallyRemovedIDs.remove(id)
    }

    /// Convenience for actions that just successfully mutated the
    /// remote resource backing this store (e.g. review add/skip,
    /// author follow/dismiss). Performs a silent load so the UI
    /// receives the post-mutation truth as quickly as possible.
    /// The apply() auto-pruning will then clean up any remaining
    /// optimistic protection for IDs the server no longer lists.
    func loadAfterLocalMutation(silent: Bool = true) async {
        if isLoadInFlight {
            await waitForCurrentLoad()
        }
        await load(silent: silent)
    }

    private func waitForCurrentLoad() async {
        guard isLoadInFlight else { return }
        await withCheckedContinuation { continuation in
            loadWaiters.append(continuation)
        }
    }

    private func resumeLoadWaiters() {
        let waiters = loadWaiters
        loadWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    private func holdSpinner(since started: ContinuousClock.Instant) async {
        let elapsed = ContinuousClock.now - started
        if elapsed < minSpinnerDuration {
            try? await Task.sleep(for: minSpinnerDuration - elapsed)
        }
    }

    private func scheduleAutomaticRetryIfNeeded() {
        guard let automaticRetryDelay,
              automaticRetryAttempts < maxAutomaticRetryAttempts else { return }
        automaticRetryAttempts += 1
        automaticRetryTask?.cancel()
        automaticRetryTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: automaticRetryDelay)
            guard !Task.isCancelled else { return }
            await self?.load(silent: true)
        }
    }

    private func resetAutomaticRetry() {
        automaticRetryAttempts = 0
        automaticRetryTask?.cancel()
        automaticRetryTask = nil
    }
}

// MARK: - Concrete factories

@MainActor
enum Stores {
    private static let intakeBase = URL(string: "http://backend.example.com:8765")!
    private static let libraryBase = URL(string: "http://backend.example.com:8766")!

    private static func intakeEndpoint(
        _ path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL {
        let url = intakeBase.appendingPathComponent(path)
        guard !queryItems.isEmpty,
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.queryItems = queryItems
        return components.url ?? url
    }

    static func backlog() -> IntakeStore<BacklogEntry, BacklogResponse> {
        IntakeStore(
            endpoint: intakeEndpoint(
                "api/backlog",
                queryItems: [URLQueryItem(name: "scope", value: "global")]
            ),
            timeoutInterval: 15,
            automaticRetryDelay: .seconds(5),
            maxAutomaticRetryAttempts: 3,
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
            automaticRetryDelay: .seconds(5),
            maxAutomaticRetryAttempts: 3,
            extract: { ($0.count, $0.entries) }
        )
    }
}

typealias BacklogStore = IntakeStore<BacklogEntry, BacklogResponse>
typealias ReviewStore = IntakeStore<ReviewEntry, ReviewResponse>
typealias AuthorStore = IntakeStore<AuthorProposal, AuthorProposalsResponse>
typealias LibraryStore = IntakeStore<LibraryEntry, LibraryResponse>
