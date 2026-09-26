import SwiftUI

/// Root flow: Camera → Result → Player. Diagnostics (Gate1RootView) from the toolbar.
struct RootFlowView: View {
    enum Route: Hashable {
        case result(CapturedPhoto)
        case player(PlayerRoute)
        case log
    }

    @State private var path: [Route] = []
    @State private var showDiagnostics = false

    var body: some View {
        NavigationStack(path: $path) {
            CameraScreen { photo in path.append(.result(photo)) }
                .navigationTitle("AI Camera - Music Reader")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button { path.append(.log) } label: { Label("Log", systemImage: "list.bullet.rectangle") }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Diagnostics") { showDiagnostics = true }
                    }
                }
                .navigationDestination(for: Route.self) { route in
                    switch route {
                    case let .result(photo):
                        ResultScreen(photo: photo) { path.append(.player($0)) }
                    case let .player(p):
                        PlayerDestination.view(for: p)
                    case .log:
                        LogScreen()
                    }
                }
        }
        .sheet(isPresented: $showDiagnostics) {
            Gate1RootView()
                .overlay(alignment: .topLeading) {
                    Button("Done") { showDiagnostics = false }
                        .padding()
                }
        }
    }
}
