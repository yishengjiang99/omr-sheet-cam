import SwiftUI

/// "N free scans left today": quiet text for free users; a tappable "See Pro" nudge at 2 or fewer left.
/// Hidden for Pro. Tapping is user-initiated, so it opens the paywall with reason `.nudge` (not capped).
struct ScansLeftLabel: View {
    enum Style { case footnote, capsule }
    var style: Style = .footnote

    @ObservedObject private var quota = ScanQuota.shared
    @ObservedObject private var storeKit = StoreKitManager.shared

    var body: some View {
        if let d = ScansLeft.display(remaining: quota.remaining, isPro: storeKit.isPro) {
            switch style {
            case .footnote: footnote(d)
            case .capsule: capsule(d)
            }
        }
    }

    @ViewBuilder
    private func footnote(_ d: ScansLeftDisplay) -> some View {
        if d.isTappable {
            Button { quota.requestPaywall(.nudge) } label: {
                HStack(spacing: 4) {
                    Text(d.text)
                    Text("See Pro").fontWeight(.semibold).foregroundStyle(Theme.coral)
                }
                .font(.footnote)
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("library.scansLeft")
        } else {
            Text(d.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("library.scansLeft")
        }
    }

    @ViewBuilder
    private func capsule(_ d: ScansLeftDisplay) -> some View {
        let label = Text(d.shortText)
            .font(.footnote.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(.black.opacity(0.4), in: Capsule())
        if d.isTappable {
            Button { quota.requestPaywall(.nudge) } label: { label }
                .accessibilityLabel("\(d.text). See Pro")
                .accessibilityIdentifier("scan.scansLeft")
        } else {
            label
                .accessibilityLabel(d.text)
                .accessibilityIdentifier("scan.scansLeft")
        }
    }
}
