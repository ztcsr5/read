import Foundation
import JavaScriptCore
import SwiftSoup

@objc protocol LegadoJavaHostExport: JSExport {
    func invoke(_ payload: JSValue) -> Any
}

/// Small command bridge used by the compatibility prelude. Public `java.*` names stay
/// identical to Legado while the actual state and side effects live in native Swift.
final class LegadoJavaHostBridge: NSObject, LegadoJavaHostExport {
    private let executionContext: RuleExecutionContext

    init(executionContext: RuleExecutionContext) {
        self.executionContext = executionContext
        super.init()
    }

    func invoke(_ payload: JSValue) -> Any {
        let dictionary = payload.toDictionary() as? [String: Any] ?? [:]
        let method = RuleExecutionContext.bridgeString(dictionary["method"])
        let arguments = dictionary["args"] as? [Any] ?? []

        switch method {
        case "put":
            guard let key = arguments.first else { return "" }
            return executionContext.put(arguments.dropFirst().first, for: RuleExecutionContext.bridgeString(key))
        case "get":
            guard let key = arguments.first else { return "" }
            return executionContext.get(RuleExecutionContext.bridgeString(key))
        case "remove":
            guard let key = arguments.first else { return false }
            executionContext.remove(RuleExecutionContext.bridgeString(key))
            return true
        case "setContent":
            let content = RuleExecutionContext.bridgeString(arguments.first)
            executionContext.setValue(content, for: "result")
            return content
        case "getContent":
            return executionContext.string(for: "result")
        case "setCookie":
            let cookie = RuleExecutionContext.bridgeString(arguments.first)
            executionContext.setValue(cookie, for: "cookieHeader")
            return cookie
        case "getCookie":
            return executionContext.string(for: "cookieHeader")
        case "log":
            let message = RuleExecutionContext.bridgeString(arguments.first)
            executionContext.log(message)
            return message
        case "ajaxAll":
            let urls: [String]
            if let values = arguments.first as? [Any] {
                urls = values.map(RuleExecutionContext.bridgeString)
            } else {
                urls = arguments.map(RuleExecutionContext.bridgeString)
            }
            return urls.map { executionContext.networkHandler?($0) ?? "" } as NSArray
        default:
            return ""
        }
    }
}

@objc protocol LegadoRuleHostExport: JSExport {
    func getElement(_ rule: String) -> LegadoElementBridge?
    func getElements(_ rule: String) -> LegadoElementsBridge
    func setContent(_ content: String) -> String
    func content() -> String
}

final class LegadoRuleHostBridge: NSObject, LegadoRuleHostExport {
    private let executionContext: RuleExecutionContext

    init(executionContext: RuleExecutionContext) {
        self.executionContext = executionContext
        super.init()
    }

    func getElement(_ rule: String) -> LegadoElementBridge? {
        getElements(rule).first()
    }

    func getElements(_ rule: String) -> LegadoElementsBridge {
        let html = executionContext.string(for: "result")
        let baseURL = executionContext.string(for: "baseUrl")
        do {
            let document = try SwiftSoup.parse(html, normalizedBaseURL(baseURL))
            let selector = normalizedSelector(rule)
            let elements = selector.isEmpty ? [document] : Array(try document.select(selector))
            return LegadoElementsBridge(elements: elements, baseURL: baseURL)
        } catch {
            executionContext.log("Rule getElements failed: \(rule) - \(error.localizedDescription)")
            return LegadoElementsBridge(elements: [], baseURL: baseURL)
        }
    }

    func setContent(_ content: String) -> String {
        executionContext.setValue(content, for: "result")
        return content
    }

    func content() -> String {
        executionContext.string(for: "result")
    }
}

@objc protocol LegadoJsoupExport: JSExport {
    func parse(_ html: String) -> LegadoElementBridge
    func parseWithBase(_ payload: JSValue) -> LegadoElementBridge
}

final class LegadoJsoupBridge: NSObject, LegadoJsoupExport {
    private let executionContext: RuleExecutionContext

    init(executionContext: RuleExecutionContext) {
        self.executionContext = executionContext
        super.init()
    }

    func parse(_ html: String) -> LegadoElementBridge {
        parse(html: html, baseURL: executionContext.string(for: "baseUrl"))
    }

    func parseWithBase(_ payload: JSValue) -> LegadoElementBridge {
        let dictionary = payload.toDictionary() as? [String: Any] ?? [:]
        return parse(
            html: RuleExecutionContext.bridgeString(dictionary["html"]),
            baseURL: RuleExecutionContext.bridgeString(dictionary["baseUrl"])
        )
    }

    private func parse(html: String, baseURL: String) -> LegadoElementBridge {
        do {
            let document = try SwiftSoup.parse(html, normalizedBaseURL(baseURL))
            return LegadoElementBridge(element: document, baseURL: baseURL)
        } catch {
            executionContext.log("Jsoup.parse failed: \(error.localizedDescription)")
            let document = try! SwiftSoup.parse("", normalizedBaseURL(baseURL))
            return LegadoElementBridge(element: document, baseURL: baseURL)
        }
    }
}

@objc protocol LegadoElementExport: JSExport {
    func select(_ selector: String) -> LegadoElementsBridge
    func text() -> String
    func ownText() -> String
    func html() -> String
    func outerHtml() -> String
    func attr(_ name: String) -> String
    func absUrl(_ name: String) -> String
    func hasAttr(_ name: String) -> Bool
    func parent() -> LegadoElementBridge?
    func parents() -> LegadoElementsBridge
    func children() -> LegadoElementsBridge
    func remove() -> LegadoElementBridge
}

final class LegadoElementBridge: NSObject, LegadoElementExport {
    fileprivate let element: SwiftSoup.Element
    fileprivate let baseURL: String

    init(element: SwiftSoup.Element, baseURL: String) {
        self.element = element
        self.baseURL = baseURL
        super.init()
    }

    func select(_ selector: String) -> LegadoElementsBridge {
        let values: [SwiftSoup.Element]
        if let selected = try? element.select(normalizedSelector(selector)) {
            values = Array(selected)
        } else {
            values = []
        }
        return LegadoElementsBridge(elements: values, baseURL: baseURL)
    }

    func text() -> String { (try? element.text()) ?? "" }
    func ownText() -> String { (try? element.ownText()) ?? "" }
    func html() -> String { (try? element.html()) ?? "" }
    func outerHtml() -> String { (try? element.outerHtml()) ?? "" }
    func attr(_ name: String) -> String {
        if ["href", "src", "data-src"].contains(name.lowercased()),
           let absolute = try? element.absUrl(name),
           !absolute.isEmpty {
            return absolute
        }
        return (try? element.attr(name)) ?? ""
    }
    func absUrl(_ name: String) -> String { (try? element.absUrl(name)) ?? "" }
    func hasAttr(_ name: String) -> Bool { element.hasAttr(name) }

    func parent() -> LegadoElementBridge? {
        guard let parent = element.parent() else { return nil }
        return LegadoElementBridge(element: parent, baseURL: baseURL)
    }

    func parents() -> LegadoElementsBridge {
        var output: [SwiftSoup.Element] = []
        var current = element.parent()
        while let parent = current {
            output.append(parent)
            current = parent.parent()
        }
        return LegadoElementsBridge(elements: output, baseURL: baseURL)
    }

    func children() -> LegadoElementsBridge {
        LegadoElementsBridge(elements: Array(element.children()), baseURL: baseURL)
    }

    func remove() -> LegadoElementBridge {
        try? element.remove()
        return self
    }
}

@objc protocol LegadoElementsExport: JSExport {
    var length: Int { get }
    func size() -> Int
    func isEmpty() -> Bool
    func get(_ index: Int) -> LegadoElementBridge?
    func first() -> LegadoElementBridge?
    func last() -> LegadoElementBridge?
    func eq(_ index: Int) -> LegadoElementBridge?
    func select(_ selector: String) -> LegadoElementsBridge
    func text() -> String
    func html() -> String
    func outerHtml() -> String
    func attr(_ name: String) -> String
    func eachText() -> NSArray
    func eachAttr(_ name: String) -> NSArray
    func children() -> LegadoElementsBridge
    func parents() -> LegadoElementsBridge
    func remove() -> LegadoElementsBridge
}

final class LegadoElementsBridge: NSObject, LegadoElementsExport {
    fileprivate var elements: [SwiftSoup.Element]
    fileprivate let baseURL: String

    init(elements: [SwiftSoup.Element], baseURL: String) {
        self.elements = elements
        self.baseURL = baseURL
        super.init()
    }

    var length: Int { elements.count }
    func size() -> Int { elements.count }
    func isEmpty() -> Bool { elements.isEmpty }

    func get(_ index: Int) -> LegadoElementBridge? {
        guard elements.indices.contains(index) else { return nil }
        return LegadoElementBridge(element: elements[index], baseURL: baseURL)
    }

    func first() -> LegadoElementBridge? { get(0) }
    func last() -> LegadoElementBridge? { get(elements.count - 1) }
    func eq(_ index: Int) -> LegadoElementBridge? { get(index >= 0 ? index : elements.count + index) }

    func select(_ selector: String) -> LegadoElementsBridge {
        let query = normalizedSelector(selector)
        let selected = elements.flatMap { element in
            guard let values = try? element.select(query) else { return [] }
            return Array(values)
        }
        return LegadoElementsBridge(elements: unique(selected), baseURL: baseURL)
    }

    func text() -> String { elements.compactMap { try? $0.text() }.joined(separator: "\n") }
    func html() -> String { elements.compactMap { try? $0.html() }.joined(separator: "\n") }
    func outerHtml() -> String { elements.compactMap { try? $0.outerHtml() }.joined(separator: "\n") }
    func attr(_ name: String) -> String {
        guard let first = elements.first else { return "" }
        return LegadoElementBridge(element: first, baseURL: baseURL).attr(name)
    }
    func eachText() -> NSArray { elements.compactMap { try? $0.text() } as NSArray }
    func eachAttr(_ name: String) -> NSArray { elements.compactMap { try? $0.attr(name) } as NSArray }

    func children() -> LegadoElementsBridge {
        LegadoElementsBridge(elements: unique(elements.flatMap { Array($0.children()) }), baseURL: baseURL)
    }

    func parents() -> LegadoElementsBridge {
        var output: [SwiftSoup.Element] = []
        for element in elements {
            var current = element.parent()
            while let parent = current {
                output.append(parent)
                current = parent.parent()
            }
        }
        return LegadoElementsBridge(elements: unique(output), baseURL: baseURL)
    }

    func remove() -> LegadoElementsBridge {
        for element in elements { try? element.remove() }
        return self
    }
}

private func normalizedBaseURL(_ baseURL: String) -> String {
    baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "http://localhost/" : baseURL
}

private func normalizedSelector(_ selector: String) -> String {
    var value = selector.trimmingCharacters(in: .whitespacesAndNewlines)
    if value.lowercased().hasPrefix("@css:") { value.removeFirst(5) }
    if value.hasPrefix("css:") { value.removeFirst(4) }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func unique(_ elements: [SwiftSoup.Element]) -> [SwiftSoup.Element] {
    var seen: Set<ObjectIdentifier> = []
    return elements.filter { seen.insert(ObjectIdentifier($0)).inserted }
}
