import SwiftUI
import UIKit

/// "Copy as prompt" button: builds the Markdown summary, copies it to `UIPasteboard`, shows a toast.
struct CopyPromptButton: View {
    var captureName: String? = nil
    var feedback: OMRFeedback? = nil
    @Binding var toast: String?

    var body: some View {
        Button {
            let text = PromptBuilder.build(.init(
                device: .current, events: DiagnosticsLog.shared.events, captureName: captureName, feedback: feedback
            ))
            UIPasteboard.general.string = text
            DiagnosticsLog.shared.record(.info, .app, "copied prompt (\(text.utf8.count) bytes)")
            toast = "Copied prompt (\(text.utf8.count) bytes)"
        } label: {
            Label("Copy as prompt", systemImage: "doc.on.clipboard")
        }
    }
}

/// Bottom toast that hides itself after ~2 s.
struct ToastModifier: ViewModifier {
    @Binding var message: String?

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16).padding(.vertical, 10)
                    .background(.thinMaterial, in: Capsule())
                    .padding(.bottom, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .task(id: message) {
                        try? await Task.sleep(nanoseconds: 2_000_000_000)
                        withAnimation { self.message = nil }
                    }
            }
        }
        .animation(.easeInOut, value: message)
    }
}

extension View {
    func toast(_ message: Binding<String?>) -> some View { modifier(ToastModifier(message: message)) }
}
