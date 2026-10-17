import SwiftUI

/// Small inline "Pro is unlimited" card (not a modal). Visible "Not now" with no delay; "See Pro" opens
/// the paywall. No pre-selected purchase, no urgency copy.
struct UpgradeCard: View {
    let message: String
    var onSeePro: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(message)
                .font(.subheadline)
            HStack {
                Button("See Pro", action: onSeePro)
                    .font(.subheadline.weight(.semibold))
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("upgradeCard.seePro")
                Spacer()
                Button("Not now", action: onDismiss)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.borderless)
                    .accessibilityIdentifier("upgradeCard.dismiss")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("result.upgradeCard")
    }
}
