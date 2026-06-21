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

    func testAjaxBridgeSupportsBodyMethodAndStringCoercion() throws {
        let runtime = JSCoreRuntime { url in
            #"{"url":"\#(url)"}"#
        }

        let result = runtime.evaluate(
            """
            var response = java.ajax('https://example.com/a');
            response.body() + '|' + JSON.parse(response).url;
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, #"{"url":"https://example.com/a"}|https://example.com/a"#)
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

    func testPostBridgeAddsExplicitHeaders() throws {
        let runtime = JSCoreRuntime { url in
            url
        }

        let result = runtime.evaluate("java.post('https://example.com/a', 'q=1', {'X-Test':'1'})")

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, #"https://example.com/a@Header:{"X-Test":"1"}@Body:q=1"#)
    }

    func testPostBridgeUsesStoredHeadersAndParams() throws {
        let runtime = JSCoreRuntime { url in
            url
        }

        let result = runtime.evaluate(
            """
            java.put('headers', {'X-Test':'1'});
            java.put('params', {'keyword':'a&b', 'page':2});
            java.post('https://example.com/a');
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, #"https://example.com/a@Header:{"X-Test":"1"}@Body:keyword=a%26b&page=2"#)
    }

    func testGetBridgeCanReadStoredVariable() throws {
        let runtime = JSCoreRuntime { url in
            "network:\(url)"
        }

        let result = runtime.evaluate(
            """
            java.put('token', 'abc');
            java.get('token');
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, "abc")
    }

    func testAjaxDoesNotConsumeStoredParamsAsBody() throws {
        let runtime = JSCoreRuntime { url in
            url
        }

        let result = runtime.evaluate(
            """
            java.put('headers', {'X-Test':'1'});
            java.put('params', {'keyword':'abc'});
            java.ajax('https://example.com/a');
            """
        )

        guard case .success(let value) = result else {
            return XCTFail("expected success")
        }
        XCTAssertEqual(value, #"https://example.com/a@Header:{"X-Test":"1"}"#)
    }
}
