#if DEBUG

import Foundation

/// Snapshot of a UI element exposed for testing. Populated by views
/// either via direct calls in `.onAppear` or (later) a view modifier.
struct ElementSnapshot: Codable, Sendable {
    let id: String
    let kind: String         // "button", "row", "textField", "list", ...
    var label: String? = nil
    var value: String? = nil
    var enabled: Bool = true
    var frame: CGRect? = nil
}

/// Type-erased Encodable wrapper so a heterogeneous `[String: any Encodable]`
/// dictionary can be JSON-encoded.
struct AnyEncodable: Encodable {
    private let _encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        self._encode = value.encode(to:)
    }
    func encode(to encoder: Encoder) throws {
        try _encode(encoder)
    }
}

/// Process-wide registry of UI elements, app state, and triggerable actions.
/// All access is on the main actor; the HTTP server hops here before reading.
///
/// Why MainActor: SwiftUI state accessed from the providers (Bindings, @Observable
/// stores) is main-actor-isolated. Keeping everything on the main actor sidesteps
/// Sendable concerns at the cost of a per-request hop, which is fine for a debug
/// server handling localhost traffic.
@MainActor
final class IntrospectionRegistry {
    static let shared = IntrospectionRegistry()
    private init() {}

    private var elements: [String: () -> ElementSnapshot] = [:]
    private var stateProviders: [String: () -> any Encodable] = [:]
    private var actions: [String: @MainActor ([String: Any]?) async -> Void] = [:]

    /// Currently focused element id. Views set this in their `.onChange(of:)`
    /// handler tied to `@FocusState`.
    var focusedId: String?

    // MARK: - Element registration

    func register(id: String, _ snapshot: @escaping () -> ElementSnapshot) {
        elements[id] = snapshot
    }

    func unregister(id: String) {
        elements.removeValue(forKey: id)
    }

    func tree() -> [ElementSnapshot] {
        elements.values.map { $0() }.sorted { $0.id < $1.id }
    }

    // MARK: - State providers

    func registerState<T: Encodable>(key: String, _ provider: @escaping () -> T) {
        stateProviders[key] = { provider() }
    }

    func unregisterState(key: String) {
        stateProviders.removeValue(forKey: key)
    }

    func stateSnapshot() -> [String: AnyEncodable] {
        var out: [String: AnyEncodable] = [:]
        for (k, v) in stateProviders {
            out[k] = AnyEncodable(v())
        }
        return out
    }

    // MARK: - Actions

    func registerAction(id: String, _ action: @escaping @MainActor () async -> Void) {
        actions[id] = { _ in await action() }
    }

    func registerAction(id: String, _ action: @escaping @MainActor ([String: Any]?) async -> Void) {
        actions[id] = action
    }

    func unregisterAction(id: String) {
        actions.removeValue(forKey: id)
    }

    func runAction(id: String, payload: [String: Any]? = nil) async -> Bool {
        guard let action = actions[id] else { return false }
        await action(payload)
        return true
    }

    func actionIDs() -> [String] {
        Array(actions.keys).sorted()
    }
}

#endif
