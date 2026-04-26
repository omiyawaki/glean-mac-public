import SwiftUI

@main
struct GleanMacApp: App {
    init() {
        #if DEBUG
        IntrospectionServer.shared.start()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
    }
}
