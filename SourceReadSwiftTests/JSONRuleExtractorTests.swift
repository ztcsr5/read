import XCTest
@testable import SourceReadSwift

final class JSONRuleExtractorTests: XCTestCase {
    func testExtractListAndFieldsByRule() throws {
        let object: [String: Any] = [
            "data": [
                "books": [
                    ["title": "斗破苍穹", "writer": "天蚕土豆", "id": "765"]
                ]
            ]
        ]
        let extractor = JSONRuleExtractor()
        let list = extractor.list(from: object, rule: "data.books")

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(extractor.string(from: list[0], rule: "title", fallbackKeys: []), "斗破苍穹")
        XCTAssertEqual(extractor.string(from: list[0], rule: "writer", fallbackKeys: []), "天蚕土豆")
    }

    func testNormalizeLegadoAndRule() throws {
        let object: [String: Any] = [
            "Data": [
                "Books": [
                    ["Name": "斗破苍穹", "BookId": 1209977]
                ]
            ]
        ]
        let extractor = JSONRuleExtractor()
        let list = extractor.list(from: object, rule: "Data&&Books")

        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(extractor.string(from: list[0], rule: "Name", fallbackKeys: []), "斗破苍穹")
        XCTAssertEqual(extractor.string(from: list[0], rule: "BookId", fallbackKeys: []), "1209977")
    }

    func testExtractBracketNotationPath() throws {
        let title = "\u{6597}\u{7834}\u{82cd}\u{7a79}"
        let object: [String: Any] = [
            "data": [
                "books": [
                    ["title": title]
                ]
            ]
        ]

        let value = JSONRuleExtractor().value(from: object, path: "$.data.books[0].title") as? String

        XCTAssertEqual(value, title)
    }

    func testExtractQuotedBracketPath() throws {
        let title = "\u{6597}\u{7834}\u{82cd}\u{7a79}"
        let object: [String: Any] = [
            "data": [
                "book-list": [
                    ["title": title]
                ]
            ]
        ]

        let value = JSONRuleExtractor().value(from: object, path: "$['data']['book-list'][0]['title']") as? String

        XCTAssertEqual(value, title)
    }

    func testExtractArrayIndexPath() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "First"],
                    ["title": "Second"]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.items[1].title") as? String
        XCTAssertEqual(value, "Second")
    }

    func testExtractWildcardPathReturnsFieldArray() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "First"],
                    ["title": "Second"]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.items[*].title") as? [Any]
        XCTAssertEqual(value as? [String], ["First", "Second"])
    }

    func testExtractNegativeArrayIndex() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "items": [
                    ["title": "First"],
                    ["title": "Second"]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.items[-1].title") as? String
        XCTAssertEqual(value, "Second")
    }

    func testExtractAtSuffixAsPathSegment() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "book": [
                    "name": "Title"
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.book@name") as? String
        XCTAssertEqual(value, "Title")
    }

    func testRegexTransformCleansJSONValue() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "intro": "<p>Hello</p>"
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.intro##<[^>]+>##") as? String
        XCTAssertEqual(value, "Hello")
    }

    func testArrayFieldIsFlattenedWhenTraversing() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "groups": [
                    ["books": [["title": "A"], ["title": "B"]]],
                    ["books": [["title": "C"]]]
                ]
            ]
        ]

        let value = extractor.value(from: object, path: "$.data.groups.books.title") as? [Any]
        XCTAssertEqual(value as? [String], ["A", "B", "C"])
    }

    func testFallbackOperatorIgnoresNestedQuotedOperatorText() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "a||b": "Primary",
                "fallback": "Fallback"
            ]
        ]

        let value = extractor.value(from: object, path: "$['data']['a||b'] || $.data.fallback") as? String
        XCTAssertEqual(value, "Primary")
    }

    func testMergeOperatorCombinesJSONArraysForStringExtraction() throws {
        let extractor = JSONRuleExtractor()
        let object: [String: Any] = [
            "data": [
                "free": [["title": "A"], ["title": "C"]],
                "vip": [["title": "B"], ["title": "D"]]
            ]
        ]

        let value = extractor.string(
            from: object,
            rule: "$.data.free.title%%$.data.vip.title",
            fallbackKeys: []
        )

        XCTAssertEqual(value, "A\nC\nB\nD")
    }
}
