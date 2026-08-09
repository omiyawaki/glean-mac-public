import Foundation

struct GleanBackendEndpoints: Equatable, Sendable {
    let intakeBase: URL
    let libraryBase: URL

    static let home = GleanBackendEndpoints(
        intakeBase: URL(string: "http://backend.example.com:8765")!,
        libraryBase: URL(string: "http://backend.example.com:8766")!
    )

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
