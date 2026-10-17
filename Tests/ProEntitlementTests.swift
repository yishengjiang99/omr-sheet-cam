import XCTest
@testable import OMRSheetCam

/// Stream A (IAP audit): one StoreKitManager app-wide (P1.12).
@MainActor
final class ProEntitlementTests: XCTestCase {
    /// P1.12: the quota gate and the UI must share one manager (one Transaction.updates listener).
    func testScanQuotaSharedUsesSharedStoreKitManager() {
        XCTAssertTrue(ScanQuota.shared.storeKit === StoreKitManager.shared,
                      "ScanQuota.shared must use StoreKitManager.shared, not its own instance")
    }

    /// P1.12: ScanQuota takes its manager by injection (no private instance).
    func testScanQuotaUsesInjectedStoreKitManager() {
        let injected = StoreKitManager()
        XCTAssertTrue(ScanQuota(storeKit: injected).storeKit === injected)
    }

    /// P1.12: no code outside StoreKitManager.swift may construct a StoreKitManager.
    func testNoStrayStoreKitManagerInstances() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/App", isDirectory: true)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        var scanned = 0
        var offenders: [String] = []
        for case let url as URL in files where url.pathExtension == "swift" {
            scanned += 1
            guard url.lastPathComponent != "StoreKitManager.swift" else { continue }
            let text = try String(contentsOf: url, encoding: .utf8)
            let code = text.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            if code.contains(where: { $0.contains("StoreKitManager()") }) { offenders.append(url.lastPathComponent) }
        }
        XCTAssertGreaterThan(scanned, 20, "source scan found too few files under \(root.path)")
        XCTAssertEqual(offenders, [], "StoreKitManager() constructed outside StoreKitManager.swift: \(offenders)")
    }
}
