import XCTest
@testable import OMRSheetCam

/// Stream A (IAP audit) P5.1 / P4.2 / P10.2: pending is not an error, users never see raw system
/// errors, and every purchase / restore attempt ends in exactly one terminal analytics event.
/// Pure logic: no StoreKit session needed (also runs on Linux via a scratch SwiftPM harness).
final class PurchaseOutcomeTests: XCTestCase {
    private let product = "com.ragnus.vp.pro.monthly"
    private let terminalPurchaseEvents: Set<String> = ["purchase_success", "purchase_cancel", "purchase_pending", "purchase_fail"]
    private let allPurchaseOutcomes: [PurchaseOutcome] =
        [.success, .cancelled, .pending, .unverified, .unknown] + PurchaseFailureKind.allCases.map { .failed($0) }

    // MARK: P5.1 pending

    func testPendingIsNotAnErrorAndIsNotAFailureEvent() {
        let r = PurchaseResolver.resolve(.pending, productID: product)
        XCTAssertEqual(r.status, .pending, "Ask to Buy must show neutral waiting state, not the red error box")
        XCTAssertEqual(r.event, "purchase_pending")
        XCTAssertFalse(r.succeeded)
    }

    func testPendingMessageIsNeutralCopy() {
        XCTAssertTrue(PurchaseResolver.pendingMessage.lowercased().contains("approv"))
        XCTAssertFalse(PurchaseResolver.pendingMessage.lowercased().contains("error"))
    }

    func testApprovalClearsPendingStatus() {
        XCTAssertEqual(PurchaseResolver.status(afterEntitlementRefresh: .pending, isPro: true), .idle)
    }

    func testPendingSurvivesRefreshWhileNotPro() {
        XCTAssertEqual(PurchaseResolver.status(afterEntitlementRefresh: .pending, isPro: false), .pending)
        XCTAssertEqual(PurchaseResolver.status(afterEntitlementRefresh: .error("x"), isPro: false), .error("x"))
    }

    // MARK: P4.2 messages

    func testUserCancelIsSilent() {
        for outcome in [PurchaseOutcome.cancelled, .failed(.cancelled)] {
            let r = PurchaseResolver.resolve(outcome, productID: product)
            XCTAssertEqual(r.status, .idle, "cancelling the Apple sheet must not show an error")
            XCTAssertEqual(r.event, "purchase_cancel")
            XCTAssertFalse(r.succeeded)
        }
    }

    func testUnverifiedPurchaseSaysCouldNotVerifyAndPointsToRestore() {
        let r = PurchaseResolver.resolve(.unverified, productID: product)
        guard case .error(let message) = r.status else { return XCTFail("expected .error, got \(r.status)") }
        XCTAssertTrue(message.lowercased().contains("verify"), message)
        XCTAssertTrue(message.contains("Restore"), message)
        XCTAssertEqual(r.props["reason"], "verification")
        XCTAssertFalse(r.succeeded)
    }

    func testEachFailureKindHasItsOwnReadableMessage() {
        let kinds = PurchaseFailureKind.allCases.filter { $0 != .cancelled }
        let messages = kinds.map { PurchaseResolver.userMessage(for: $0) }
        XCTAssertEqual(Set(messages).count, kinds.count, "messages must be distinct per failure kind: \(messages)")
        for m in messages {
            XCTAssertFalse(m.isEmpty)
            XCTAssertFalse(m.contains("operation couldn't be completed"), "raw system wording leaked: \(m)")
            XCTAssertFalse(m.contains("error 0") || m.contains("StoreKit") || m.contains("Swift"), m)
        }
        XCTAssertTrue(PurchaseResolver.userMessage(for: .network).lowercased().contains("connection"))
    }

    func testUnknownStoreKitResultShowsGenericMessage() {
        let r = PurchaseResolver.resolve(.unknown, productID: product)
        guard case .error(let message) = r.status else { return XCTFail("@unknown default must not be silent, got \(r.status)") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertEqual(r.props["reason"], "unknown")
    }

    func testFailureEventReasonIsTheCoarseKind() {
        for kind in PurchaseFailureKind.allCases where kind != .cancelled {
            let r = PurchaseResolver.resolve(.failed(kind), productID: product)
            XCTAssertEqual(r.event, "purchase_fail")
            XCTAssertEqual(r.props["reason"], kind.rawValue)
        }
    }

    // MARK: P10.2 terminal events

    func testEveryPurchaseOutcomeEndsInExactlyOneKnownTerminalEvent() {
        for outcome in allPurchaseOutcomes {
            let r = PurchaseResolver.resolve(outcome, productID: product)
            guard let event = r.event else { XCTFail("\(outcome) emitted no terminal event"); continue }
            XCTAssertTrue(terminalPurchaseEvents.contains(event), "\(outcome) -> unexpected event \(event)")
        }
    }

    func testOnlySuccessSucceeds() {
        for outcome in allPurchaseOutcomes {
            XCTAssertEqual(PurchaseResolver.resolve(outcome, productID: product).succeeded, outcome == .success, "\(outcome)")
        }
    }

    func testSuccessEventCarriesProduct() {
        let r = PurchaseResolver.resolve(.success, productID: product)
        XCTAssertEqual(r.event, "purchase_success")
        XCTAssertEqual(r.props["product"], product)
        XCTAssertEqual(r.status, .idle)
    }

    func testEveryRestoreOutcomeEndsInExactlyOneKnownTerminalEvent() {
        let expected: [(RestoreOutcome, String)] = [
            (.restored, "restore_success"), (.nothingToRestore, "restore_none"), (.cancelled, "restore_cancel"),
            (.failed(.network), "restore_fail"),
        ]
        for (outcome, event) in expected {
            XCTAssertEqual(PurchaseResolver.resolve(outcome).event, event, "\(outcome)")
        }
    }

    func testRestoreMessages() {
        XCTAssertNil(PurchaseResolver.resolve(.restored).errorMessage)
        XCTAssertNil(PurchaseResolver.resolve(.cancelled).errorMessage, "dismissing the Apple ID prompt is silent")
        XCTAssertNil(PurchaseResolver.resolve(.nothingToRestore).errorMessage)
        let failed = PurchaseResolver.resolve(.failed(.network))
        XCTAssertEqual(failed.errorMessage, PurchaseResolver.userMessage(for: .network))
        XCTAssertEqual(failed.props["reason"], "network")
    }
}
