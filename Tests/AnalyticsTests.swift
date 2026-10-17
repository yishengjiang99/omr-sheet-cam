import XCTest
@testable import OMRSheetCam

/// P10.3: the PII key filter must drop PII-looking keys only. `platform` used to be dropped because
/// the unanchored regex matched "lat" inside "platform". The test intercepts the real telemetry POST
/// (URLProtocol on the shared session) and inspects the JSON `props`.
final class AnalyticsTests: XCTestCase {
    final class CapturingProtocol: URLProtocol {
        nonisolated(unsafe) static var bodies: [[String: Any]] = []
        static let lock = NSLock()
        override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "photo.grepawk.com" }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var data = request.httpBody ?? Data()
            if data.isEmpty, let s = request.httpBodyStream {
                s.open()
                var buf = [UInt8](repeating: 0, count: 4096)
                while s.hasBytesAvailable {
                    let n = s.read(&buf, maxLength: buf.count)
                    if n <= 0 { break }
                    data.append(buf, count: n)
                }
                s.close()
            }
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                Self.lock.lock(); Self.bodies.append(obj); Self.lock.unlock()
            }
            let resp = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: resp, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data())
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        CapturingProtocol.bodies = []
        URLProtocol.registerClass(CapturingProtocol.self)
    }

    override func tearDown() {
        URLProtocol.unregisterClass(CapturingProtocol.self)
        super.tearDown()
    }

    @MainActor
    func testTrackKeepsPlatformAndOtherLegitKeysAndDropsPII() async throws {
        let event = "p10_3_probe_\(UUID().uuidString.prefix(6))"
        Analytics.shared.track(event, props: [
            "platform": "ios", "app_version": "1.0", "plan": "yearly", "product": "com.ragnus.vp.pro.yearly",
            "reason": "quota", "latency_ms": "12", "template": "t", "relation": "r",
            "email": "a@b.c", "lat": "37.1", "lng": "-122.2", "gps": "x", "token": "t0k", "password": "p",
            "user_email": "a@b.c", "photo": "x", "image": "x", "base64": "x",
            "too_long": String(repeating: "x", count: 201),
        ])
        var props: [String: Any]?
        for _ in 0 ..< 40 where props == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
            CapturingProtocol.lock.lock()
            props = CapturingProtocol.bodies.first { $0["event"] as? String == event }?["props"] as? [String: Any]
            CapturingProtocol.lock.unlock()
        }
        let sent = try XCTUnwrap(props, "telemetry POST for \(event) was not observed")
        for k in ["platform", "app_version", "plan", "product", "reason", "latency_ms", "template", "relation"] {
            XCTAssertNotNil(sent[k], "legit prop \(k) was dropped; sent keys: \(sent.keys.sorted())")
        }
        for k in ["email", "lat", "lng", "gps", "token", "password", "user_email", "photo", "image", "base64", "too_long"] {
            XCTAssertNil(sent[k], "prop \(k) must not be sent")
        }
    }

    func testCleanKeepsLegitKeysAndDropsPIIKeys() {
        let kept = Analytics.clean(props: ["platform": "ios", "plan": "monthly", "product": "p", "reason": "quota", "app_version": "1.0",
                                           "latency_ms": "5", "translate": "x", "relation": "x", "template": "x", "ms": "9", "notes": "4"])
        XCTAssertEqual(Set(kept.keys), ["platform", "plan", "product", "reason", "app_version", "latency_ms", "translate", "relation", "template", "ms", "notes"])
        let dropped = Analytics.clean(props: ["email": "a", "Email": "a", "user_email": "a", "phone": "1", "lat": "1", "lng": "1", "gps": "1",
                                              "gpsLat": "1", "userLat": "1", "device-token": "t", "password": "p", "photo": "x", "image": "x",
                                              "base64": "x", "image_data": "x", "longitude": "1"])
        XCTAssertTrue(dropped.isEmpty, "should have dropped everything, kept \(dropped.keys.sorted())")
    }

    func testCleanDropsBulkyValuesAndCapsLength() {
        XCTAssertNil(Analytics.clean(props: ["note": "data:image/png;base64,AAAA"])["note"])
        XCTAssertNil(Analytics.clean(props: ["note": String(repeating: "x", count: 201)])["note"])
        XCTAssertEqual(Analytics.clean(props: ["note": String(repeating: "x", count: 200)])["note"]?.count, 200)
    }

    func testKeyWordSplitting() {
        XCTAssertEqual(Analytics.keyWords("platform"), ["platform"])
        XCTAssertEqual(Analytics.keyWords("gpsLat"), ["gps", "lat"])
        XCTAssertEqual(Analytics.keyWords("user_email-id.v2"), ["user", "email", "id", "v2"])
    }
}
