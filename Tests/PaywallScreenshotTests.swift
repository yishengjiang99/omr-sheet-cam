import SwiftUI
import StoreKit
import StoreKitTest
import UIKit
import XCTest
@testable import OMRSheetCam

/// Captures the real "Music Reader Pro" paywall for the App Store subscription review screenshot.
/// Opt-in only (ios-screenshots workflow): TEST_RUNNER_OMR_PAYWALL_SHOT=1 and
/// TEST_RUNNER_OMR_PAYWALL_OUT=<host dir>. Loads products from OMRSheetCam.storekit through
/// SKTestSession (this hosted test runs in the app process), presents PaywallView full screen,
/// writes <out>/paywall-ready, then holds the screen so the workflow can `simctl io screenshot` it.
final class PaywallScreenshotTests: XCTestCase {
    @MainActor
    func testCapturePaywallForReview() async throws {
        let env = ProcessInfo.processInfo.environment
        guard env["OMR_PAYWALL_SHOT"] == "1", let outPath = env["OMR_PAYWALL_OUT"] else {
            throw XCTSkip("opt-in: TEST_RUNNER_OMR_PAYWALL_SHOT=1 TEST_RUNNER_OMR_PAYWALL_OUT=<dir>")
        }
        let out = URL(fileURLWithPath: outPath, isDirectory: true)
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
        let session = try SKTestSession(contentsOf: repo.appendingPathComponent("OMRSheetCam.storekit"))
        session.disableDialogs = true
        session.clearTransactions()
        UserDefaults.standard.set(false, forKey: "omr.isPro")

        let store = StoreKitManager()
        for _ in 0..<10 where store.monthlyProduct == nil || store.yearlyProduct == nil {
            await store.loadProducts()
            if store.monthlyProduct == nil { try await Task.sleep(nanoseconds: 1_000_000_000) }
        }
        let monthly = try XCTUnwrap(store.monthlyProduct, "monthly not loaded: \(store.purchaseError ?? "-")")
        let yearly = try XCTUnwrap(store.yearlyProduct, "yearly not loaded: \(store.purchaseError ?? "-")")
        print("[paywall-shot] monthly=\(monthly.displayPrice) yearly=\(yearly.displayPrice)")
        XCTAssertEqual(monthly.displayPrice, "$4.99")
        XCTAssertEqual(yearly.displayPrice, "$29.99")

        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow) ?? scene.windows.first)
        var top = try XCTUnwrap(window.rootViewController)
        while let presented = top.presentedViewController { top = presented }
        let host = UIHostingController(rootView: PaywallView().environmentObject(store).tint(Theme.coral))
        host.modalPresentationStyle = .fullScreen
        top.present(host, animated: false)
        try await Task.sleep(nanoseconds: 4_000_000_000)
        XCTAssertFalse(store.products.isEmpty)

        // In-process render as a fallback artifact (no status bar).
        let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("paywall-render.png"))
        try Data("ready".utf8).write(to: out.appendingPathComponent("paywall-ready"))
        // Hold until the workflow has taken the simulator screenshot (it writes paywall-done).
        for _ in 0..<60 where !FileManager.default.fileExists(atPath: out.appendingPathComponent("paywall-done").path) {
            try await Task.sleep(nanoseconds: 1_000_000_000)
        }
        host.dismiss(animated: false)
        withExtendedLifetime(session) {}
    }
}
