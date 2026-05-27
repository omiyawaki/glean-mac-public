import Foundation
import WebKit

enum GleanWebDataStore {
    private static let stableSharedIdentifier = UUID(
        uuidString: "D89C8F2F-81B7-4A50-8E8D-0C8742F69C35"
    )!

    static func identifier(forBundleIdentifier bundleIdentifier: String? = nil) -> UUID {
        stableSharedIdentifier
    }

    static func migrationFlagKey(forBundleIdentifier bundleIdentifier: String?) -> String {
        let bundle = bundleIdentifier?.isEmpty == false
            ? bundleIdentifier!
            : "unknown"
        return "GleanSharedWebDataStoreMigratedDefaultData.\(bundle)"
    }

    @MainActor
    static func websiteDataStore(
        userDefaults: UserDefaults = .standard,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) -> WKWebsiteDataStore {
        guard #available(macOS 14.0, *) else {
            return .default()
        }
        let store = WKWebsiteDataStore(forIdentifier: identifier(
            forBundleIdentifier: bundleIdentifier
        ))
        migrateDefaultDataIfNeeded(
            to: store,
            userDefaults: userDefaults,
            bundleIdentifier: bundleIdentifier
        )
        return store
    }

    @MainActor
    private static func migrateDefaultDataIfNeeded(
        to destination: WKWebsiteDataStore,
        userDefaults: UserDefaults,
        bundleIdentifier: String?
    ) {
        guard #available(macOS 26.0, *) else { return }
        let key = migrationFlagKey(forBundleIdentifier: bundleIdentifier)
        guard !userDefaults.bool(forKey: key) else { return }

        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().fetchData(of: types) { data, error in
            guard error == nil else { return }
            guard let data, !data.isEmpty else {
                userDefaults.set(true, forKey: key)
                return
            }
            destination.restoreData(data) { error in
                guard error == nil else { return }
                userDefaults.set(true, forKey: key)
            }
        }
    }
}

