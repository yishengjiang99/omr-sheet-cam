import OMRScanKit
import SwiftUI

/// Redesign 02-reading: the page with a moving scan line and a progress card while recognition
/// runs on-device ("Reading music… 42%" + determinate bar fed by the real page pipeline progress,
/// `RecognitionProgress`). Cancel pops back to Scan (which cancels the recognition task).
public struct ReadingView: View {
    let image: UIImage?
    /// Recognition progress 0...1 (`RecognitionProgress.fraction`).
    var fraction: Double = 0
    /// `true` while the scan is blocked on the model warmup ("Warming up… x%").
    var warmingUp: Bool = false
    /// Seconds of warmup remaining (ticking estimate); shown under the title while warming up.
    var etaSeconds: Double? = nil
    /// `true` when the warmup is reloading the models after a memory-warning release.
    var isRewarm: Bool = false
    var onCancel: () -> Void

    public init(
        image: UIImage?, fraction: Double = 0, warmingUp: Bool = false, etaSeconds: Double? = nil,
        isRewarm: Bool = false, onCancel: @escaping () -> Void
    ) {
        self.image = image; self.fraction = fraction; self.warmingUp = warmingUp
        self.etaSeconds = etaSeconds; self.isRewarm = isRewarm; self.onCancel = onCancel
    }

    /// "Reading music… 42%" / "Warming up… 42%".
    public static func title(fraction: Double, warmingUp: Bool = false) -> String {
        let name = warmingUp ? ScanStrings.string("reading.title.warming", "Warming up")
                             : ScanStrings.string("reading.title.reading", "Reading music")
        return "\(name)… \(Int((min(max(fraction, 0), 1) * 100).rounded(.down)))%"
    }

    /// Subtitle under the bar; while warming up shows the ticking ETA when known.
    public static func subtitle(warmingUp: Bool, etaSeconds: Double?, isRewarm: Bool = false) -> String {
        guard warmingUp else { return ScanStrings.string("reading.subtitle.reading", "This usually takes a few seconds") }
        if isRewarm {
            if let eta = etaSeconds, eta > 1 {
                return ScanStrings.format("reading.subtitle.rewarm.eta", "About %d seconds left · reloading the music models", Int(eta.rounded()))
            }
            return ScanStrings.string("reading.subtitle.rewarm", "Reloading the music models on your iPhone")
        }
        if let eta = etaSeconds, eta > 1 {
            return ScanStrings.format("reading.subtitle.warm.eta", "About %d seconds left · one-time setup", Int(eta.rounded()))
        }
        return ScanStrings.string("reading.subtitle.warm", "One-time setup — loading the music models on your iPhone")
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scanTheme) private var theme
    @State private var sweep = false

    public var body: some View {
        ZStack {
            theme.background.ignoresSafeArea()
            VStack(spacing: 20) {
                HStack {
                    Button(ScanStrings.string("reading.cancel", "Cancel"), action: onCancel)
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

    @ViewBuilder private var page: some View {
        if let image { pageImage(image) } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.08))
                .frame(maxWidth: .infinity).frame(height: 240)
                .accessibilityHidden(true)
        }
    }

    private func pageImage(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                GeometryReader { geo in
                    LinearGradient(colors: [theme.accent.opacity(0), theme.accent.opacity(0.35), theme.accent.opacity(0)],
                                   startPoint: .top, endPoint: .bottom)
                        .frame(height: 60)
                        .overlay(Rectangle().fill(theme.accent).frame(height: 2))
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
            VStack(alignment: .leading, spacing: 8) {
                Text(Self.title(fraction: fraction, warmingUp: warmingUp))
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .accessibilityIdentifier("reading.percent")
                ProgressView(value: min(max(fraction, 0), 1))
                    .progressViewStyle(.linear)
                    .tint(theme.accent)
                    .animation(.easeOut(duration: 0.25), value: fraction)
                Text(Self.subtitle(warmingUp: warmingUp, etaSeconds: etaSeconds, isRewarm: isRewarm))
                    .font(.subheadline).foregroundStyle(.white.opacity(0.7))
            }
            Label(ScanStrings.string("reading.privacy", "Read on your iPhone. No internet needed."), systemImage: "lock.fill")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.7))
        }
        .foregroundStyle(theme.foreground)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.cardBackground, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("reading.progress")
    }
}
