import XCTest
@testable import GleanMac

final class GleanWebDataStoreTests: XCTestCase {
    func testMigrationFlagIsScopedToBundleIdentifier() {
        XCTAssertEqual(
            GleanWebDataStore.migrationFlagKey(
                forBundleIdentifier: "com.miyawaki.glean-mac"
            ),
            "GleanSharedWebDataStoreMigratedDefaultData.com.miyawaki.glean-mac"
        )
    }
}

