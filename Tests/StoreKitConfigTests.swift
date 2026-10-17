import StoreKit
import StoreKitTest
import XCTest
@testable import OMRSheetCam

/// P11.3: OMRSheetCam.storekit must be wired into the project + shared scheme (Run > Options >
/// StoreKit Configuration), and the config must actually serve both Pro products.
/// File-based checks read the repo (located via #filePath, same trick as PaywallScreenshotTests).
final class StoreKitConfigTests: XCTestCase {
    private let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    private var xcodeproj: URL { repo.appendingPathComponent("OMRSheetCam.xcodeproj") }

    /// Collects `identifier` of every <StoreKitConfigurationFileReference> and the action it sits in.
    private final class SchemeParser: NSObject, XMLParserDelegate {
        var stack: [String] = []
        var refs: [(action: String, identifier: String)] = []
        func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                    qualifiedName: String?, attributes: [String: String] = [:]) {
            if name == "StoreKitConfigurationFileReference" {
                refs.append((stack.last ?? "?", attributes["identifier"] ?? ""))
            }
            stack.append(name)
        }
        func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
            _ = stack.popLast()
        }
    }

    func testSharedSchemeAttachesStoreKitConfigToRunAction() throws {
        let scheme = xcodeproj.appendingPathComponent("xcshareddata/xcschemes/OMRSheetCam.xcscheme")
        let parser = XMLParser(data: try Data(contentsOf: scheme))
        let delegate = SchemeParser()
        parser.delegate = delegate
        XCTAssertTrue(parser.parse(), "scheme XML must parse: \(String(describing: parser.parserError))")
        let launch = delegate.refs.filter { $0.action == "LaunchAction" }
        XCTAssertEqual(launch.count, 1, "LaunchAction needs exactly one StoreKitConfigurationFileReference (found \(delegate.refs))")
        let id = try XCTUnwrap(launch.first?.identifier)
        // Xcode resolves the identifier relative to the (implicit) workspace inside the .xcodeproj.
        let resolved = URL(fileURLWithPath: id, relativeTo: xcodeproj.appendingPathComponent("project.xcworkspace", isDirectory: true)).standardizedFileURL
        XCTAssertEqual(resolved.lastPathComponent, "OMRSheetCam.storekit")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resolved.path), "identifier \(id) resolves to \(resolved.path), which does not exist")
        XCTAssertEqual(resolved.path, repo.appendingPathComponent("OMRSheetCam.storekit").standardizedFileURL.path)
    }

    func testProjectReferencesStoreKitFile() throws {
        let pbx = try String(contentsOf: xcodeproj.appendingPathComponent("project.pbxproj"), encoding: .utf8)
        XCTAssertTrue(pbx.contains("path = OMRSheetCam.storekit;"), "project.pbxproj has no file reference for OMRSheetCam.storekit")
        XCTAssertFalse(pbx.contains("OMRSheetCam.storekit in Resources"), "the .storekit must not ship in the app bundle")
    }

    @MainActor
    func testStoreKitConfigServesBothProProducts() async throws {
        let session = try SKTestSession(contentsOf: repo.appendingPathComponent("OMRSheetCam.storekit"))
        session.disableDialogs = true
        session.clearTransactions()
        let products = try await Product.products(for: IAPProductID.all)
        XCTAssertEqual(Set(products.map(\.id)), IAPProductID.all)
        XCTAssertEqual(products.first { $0.id == IAPProductID.monthly }?.displayPrice, "$4.99")
        XCTAssertEqual(products.first { $0.id == IAPProductID.yearly }?.displayPrice, "$29.99")
        withExtendedLifetime(session) {}
    }
}
