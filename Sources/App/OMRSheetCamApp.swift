import SwiftUI

@main
struct OMRSheetCamApp: App {
    init() {
        // ORT / CoreML session warmup stub (no-op until models are bundled).
        SessionWarmup.warmupAtLaunch()
    }

    var body: some Scene {
        WindowGroup {
            Gate1RootView()
        }
    }
}
