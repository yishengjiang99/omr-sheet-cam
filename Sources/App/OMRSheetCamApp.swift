import SwiftUI

@main
struct OMRSheetCamApp: App {
    init() {
        // Background model warmup (off the main thread). Skipped when hosting XCTest: tests
        // drive ModelWarmup themselves.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            ModelWarmup.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootFlowView()
        }
    }
}
