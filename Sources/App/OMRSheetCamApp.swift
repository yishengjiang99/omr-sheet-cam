import SwiftUI

@main
struct OMRSheetCamApp: App {
    // The ONE app-wide player (PlaybackController.shared) is injected below via .environmentObject.
    init() {
        DiagnosticsLog.installUncaughtExceptionHandler()
        let device = DeviceInfo.current
        DiagnosticsLog.shared.record(.info, .app, "launch \(device.headerLine)", payload: device.payload)
        // Background model warmup (off the main thread). Skipped when hosting XCTest: tests
        // drive ModelWarmup themselves.
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil {
            ModelWarmup.shared.start()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootFlowView()
                .environmentObject(PlaybackController.shared)
        }
    }
}
