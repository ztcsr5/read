import XCTest
@testable import SourceReadSwift

final class JSCoreNetworkBridgeTests: XCTestCase {
    func testAjaxBridgeUsesInjectedHandler() throws {
        let runtime = JSCoreRuntime { url in
            "loaded:\(url)"
        }

        let result = runtime.evaluate("java.ajax('https://example.com/a')")

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "loaded:https://example.com/a")
    }

    func testPostBridgeAddsBodyDirective() throws {
        let runtime = JSCoreRuntime { url in
            url
        }

        let result = runtime.evaluate("java.post('https://example.com/a', 'q=1')")

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "https://example.com/a@Body:q=1")
    }
}
