import Foundation

struct GleanBackendEndpoints: Equatable, Sendable {
    let intakeBase: URL
    let libraryBase: URL

    /// Endpoints used by the app. Resolution order for each base URL:
    /// environment variable, then the `UserDefaults` key, then a localhost
    /// default.
    ///
    /// - `GLEAN_INTAKE_URL` / `GleanIntakeURL` (default `http://localhost:8765`)
    /// - `GLEAN_LIBRARY_URL` / `GleanLibraryURL` (default `http://localhost:8766`)
    ///
    /// Apps launched from Finder do not inherit shell variables, so use
    /// `defaults write <bundle id> GleanIntakeURL http://host:8765` there.
    static let configured = resolve(
        environment: ProcessInfo.processInfo.environment,
        defaults: .standard
    )

    static let defaultIntakeBase = URL(string: "http://localhost:8765")!
    static let defaultLibraryBase = URL(string: "http://localhost:8766")!

    static func resolve(
        environment: [String: String],
        defaults: UserDefaults
    ) -> GleanBackendEndpoints {
        func base(envKey: String, defaultsKey: String, fallback: URL) -> URL {
            for raw in [environment[envKey], defaults.string(forKey: defaultsKey)] {
                if let raw,
                   !raw.isEmpty,
                   let url = URL(string: raw),
                   url.scheme != nil,
                   url.host != nil {
                    return url
                }
            }
            return fallback
        }
        return GleanBackendEndpoints(
            intakeBase: base(
                envKey: "GLEAN_INTAKE_URL",
                defaultsKey: "GleanIntakeURL",
                fallback: defaultIntakeBase
            ),
            libraryBase: base(
                envKey: "GLEAN_LIBRARY_URL",
                defaultsKey: "GleanLibraryURL",
                fallback: defaultLibraryBase
            )
        )
    }

    var eventsURL: URL {
        intakeURL(path: "events")
    }

    var backlogURL: URL {
        intakeURL(
            path: "api/backlog",
            queryItems: [URLQueryItem(name: "scope", value: "global")]
        )
    }

    func intakeURL(
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL {
        endpoint(base: intakeBase, path: path, queryItems: queryItems)
    }

    func libraryURL(path: String) -> URL {
        endpoint(base: libraryBase, path: path)
    }

    func libraryDetailURL(citekey: String) -> URL {
        libraryPaperURL(citekey: citekey)
    }

    func libraryRelationURL(citekey: String, kind: LibraryRelationKind) -> URL {
        libraryPaperURL(citekey: citekey, suffix: kind.apiPathComponent)
    }

    func libraryReferenceRetryURL(citekey: String) -> URL {
        libraryPaperURL(citekey: citekey, suffix: "references/retry")
    }

    func libraryAttachmentPlanURL(citekey: String) -> URL {
        libraryPaperURL(citekey: citekey, suffix: "attachment-plan")
    }

    func libraryAttachmentCommitURL(citekey: String) -> URL {
        libraryPaperURL(citekey: citekey, suffix: "attachment-commit")
    }

    func libraryAttachmentReleaseURL(citekey: String) -> URL {
        libraryPaperURL(citekey: citekey, suffix: "attachment-release")
    }

    func libraryPDFURL(citekey: String) -> URL {
        libraryPaperURL(citekey: citekey, suffix: "pdf")
    }

    var graphStatusURL: URL {
        libraryURL(path: "api/graph/status")
    }

    private func libraryPaperURL(citekey: String, suffix: String? = nil) -> URL {
        let papersURL = endpoint(base: libraryBase, path: "api/papers")
        guard var components = URLComponents(
            url: papersURL,
            resolvingAgainstBaseURL: false
        ) else {
            return papersURL.appendingPathComponent(citekey)
        }
        let allowed = CharacterSet.urlPathAllowed.subtracting(
            CharacterSet(charactersIn: "/")
        )
        let encoded = citekey.addingPercentEncoding(
            withAllowedCharacters: allowed
        ) ?? citekey
        components.percentEncodedPath += "/\(encoded)"
        if let suffix {
            components.percentEncodedPath += "/\(suffix)"
        }
        return components.url ?? papersURL.appendingPathComponent(citekey)
    }

    private func endpoint(
        base: URL,
        path: String,
        queryItems: [URLQueryItem] = []
    ) -> URL {
        let url = path.split(separator: "/").reduce(base) { partial, component in
            partial.appendingPathComponent(String(component))
        }
        guard !queryItems.isEmpty,
              var components = URLComponents(
                  url: url,
                  resolvingAgainstBaseURL: false
              ) else {
            return url
        }
        components.queryItems = queryItems
        return components.url ?? url
    }
}
