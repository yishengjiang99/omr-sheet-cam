import XCTest
@testable import OMRSheetCam

/// P2.5 (paywall load failure: one message, Retry, no error flash) and P6.3 (Restore feedback).
/// Pure logic (also runs on Linux via a scratch SwiftPM harness).
final class PaywallStateTests: XCTestCase {
    func testFirstFrameShowsSpinnerAndNoError() {
        for state in [PaywallLoadState.idle, .loading] {
            let d = PaywallState.display(state, hasProducts: false)
            XCTAssertTrue(d.showsSpinner, "\(state): spinner while not yet loaded")
            XCTAssertEqual(d.messages, [], "\(state): no error text before the request has even started")
            XCTAssertFalse(d.showsRetry)
            XCTAssertFalse(d.showsProducts)
        }
    }

    func testFailedLoadShowsExactlyOneMessageAndRetry() {
        let d = PaywallState.display(.failed("Couldn't reach the App Store."), hasProducts: false)
        XCTAssertEqual(d.messages, ["Couldn't reach the App Store."], "one message, not two")
        XCTAssertTrue(d.showsRetry)
        XCTAssertFalse(d.showsSpinner)
    }

    func testLoadedButEmptyShowsOneMessageAndRetry() {
        let d = PaywallState.display(.loaded, hasProducts: false)
        XCTAssertEqual(d.messages, [PaywallState.emptyMessage])
        XCTAssertTrue(d.showsRetry)
    }

    func testLoadedWithProductsShowsProductsOnly() {
        let d = PaywallState.display(.loaded, hasProducts: true)
        XCTAssertEqual(d, PaywallProductsDisplay(showsSpinner: false, showsProducts: true, messages: [], showsRetry: false))
    }

    func testReloadKeepsExistingProductsVisible() {
        let d = PaywallState.display(.loading, hasProducts: true)
        XCTAssertTrue(d.showsProducts)
        XCTAssertFalse(d.showsSpinner)
    }

    func testLoadFailureMessagesArePlainLanguage() {
        for kind in PurchaseFailureKind.allCases {
            let m = PaywallState.loadFailureMessage(for: kind)
            XCTAssertFalse(m.isEmpty)
            XCTAssertFalse(m.contains("StoreKit") || m.contains("error 0") || m.contains("operation couldn't"), m)
        }
        XCTAssertTrue(PaywallState.loadFailureMessage(for: .network).lowercased().contains("connection"))
        XCTAssertNotEqual(PaywallState.loadFailureMessage(for: .network), PaywallState.loadFailureMessage(for: .notAvailable))
    }

    func testRestoreFeedback() {
        XCTAssertEqual(RestoreFeedback.resolve(.restored), RestoreFeedback(text: "Pro restored", isError: false, dismissPaywall: true))
        XCTAssertEqual(
            RestoreFeedback.resolve(.nothingToRestore),
            RestoreFeedback(text: "No active subscription found for this Apple ID", isError: false, dismissPaywall: false))
        XCTAssertEqual(RestoreFeedback.resolve(.cancelled), RestoreFeedback(text: nil, isError: false, dismissPaywall: false),
                       "dismissing the Apple ID prompt is silent")
        XCTAssertEqual(
            RestoreFeedback.resolve(.failed(.network)),
            RestoreFeedback(text: PurchaseResolver.userMessage(for: .network), isError: true, dismissPaywall: false))
    }
}
