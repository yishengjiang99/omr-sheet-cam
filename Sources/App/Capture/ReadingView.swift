import SwiftUI

/// Redesign 02-reading: the page with a moving scan line and a progress card while recognition
/// runs on-device. Cancel pops back to Scan (which cancels the recognition task).
struct ReadingView: View {
    let image: UIImage
    var onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var sweep = false

    var body: some View {
        ZStack {
            Color(white: 0.07).ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button("Cancel", action: onCancel)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 14).padding(.vertical, 8)
                        .background(.white.opacity(0.14), in: Capsule())
                        .accessibilityIdentifier("reading.cancel")
                    Spacer()
                }
                page
                Spacer(minLength: 0)
                card
            }
            .padding(20)
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.easeInOut(duration: 1.6).repeatForever(autoreverses: true)) { sweep = true }
        }
    }

    private var page: some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [Theme.coral.opacity(0), Theme.coral.opacity(0.35), Theme.coral.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                        .overlay(Rectangle().fill(Theme.coral).frame(height: 2))
                        .offset(y: sweep ? geo.size.height - 30 : -30)
                }
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .allowsHitTesting(false)
            }
            .frame(maxHeight: 440)
            .accessibilityHidden(true)
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 14) {
                ProgressView().tint(Theme.coral).controlSize(.large)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Reading your music…").font(.title3.weight(.bold))
                    Text("This usually takes a few seconds").font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
            }
            Label("Read on your iPhone. No internet needed.", systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reading.progress")
    }
}
