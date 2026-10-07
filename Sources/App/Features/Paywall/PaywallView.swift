import SwiftUI
import StoreKit

struct PaywallView: View {
    @EnvironmentObject private var storeKit: StoreKitManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Text("Music Reader Pro")
                        .font(.largeTitle.bold())
                        .multilineTextAlignment(.center)

                    Text("Free: 5 page scans a day. Music Reader Pro unlocks unlimited scans.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    if let yearly = storeKit.yearlyProduct {
                        planCard(product: yearly, title: "Yearly", primary: true)
                    }
                    if let monthly = storeKit.monthlyProduct {
                        planCard(product: monthly, title: "Monthly", primary: false)
                    }
                    if storeKit.products.isEmpty && !storeKit.isLoading {
                        Text("Could not load products. Check your connection and try again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    comparison

                    if let err = storeKit.purchaseError {
                        Text(err)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding()
                            .background(RoundedRectangle(cornerRadius: 8).fill(Color.red.opacity(0.1)))
                    }

                    Button("Restore purchases") {
                        Task { await storeKit.restore() }
                    }
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                    legal
                }
                .padding()
            }
            .navigationTitle("Upgrade")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { Analytics.shared.track("paywall_view") }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await storeKit.loadProducts() }
        }
    }

    private func planCard(product: Product, title: String, primary: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.headline)
                Spacer()
                if primary {
                    Text("Best value")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.accentColor))
                }
            }
            Text(product.displayPrice)
                .font(.largeTitle.bold())
            Button {
                Task {
                    Analytics.shared.track("paywall_plan_select", props: ["plan": title.lowercased()])
                    let ok = await storeKit.purchase(product)
                    if ok { dismiss() }
                }
            } label: {
                HStack {
                    if storeKit.isPurchasing { ProgressView() }
                    Text("Subscribe")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(storeKit.isPurchasing)
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(primary ? Color.accentColor : Color.secondary.opacity(0.3), lineWidth: primary ? 2 : 1)
        )
    }

    private var comparison: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Free").font(.subheadline.bold()).foregroundStyle(.secondary)
                featureRow("5 scans / day", pro: false)
                featureRow("On-device reading & playback", pro: false)
                featureRow("All instruments", pro: false)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .leading, spacing: 8) {
                Text("Pro").font(.subheadline.bold())
                featureRow("Unlimited scans", pro: true)
                featureRow("Same player & instruments", pro: true)
                featureRow("Same on-device recognition", pro: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }

    private func featureRow(_ text: String, pro: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checkmark")
                .font(.caption2.bold())
                .foregroundStyle(pro ? Color.accentColor : Color.secondary)
            Text(text).font(.caption).foregroundStyle(pro ? .primary : .secondary)
        }
    }

    private var legal: some View {
        VStack(spacing: 6) {
            Text("Payment charged to your Apple ID. Renews unless canceled 24h before period end. Manage in Settings → Apple ID → Subscriptions.")
                .font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
            HStack(spacing: 20) {
                Link("Terms of Use", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                    .font(.caption)
                Link("Privacy Policy", destination: URL(string: "https://grepawk.com/music-reader/privacy.html")!)
                    .font(.caption)
            }
        }
    }
}
