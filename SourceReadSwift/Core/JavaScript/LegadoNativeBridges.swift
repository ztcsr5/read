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
    private let services: LegadoHostServices

    init(executionContext: RuleExecutionContext) {
        self.executionContext = executionContext
        self.services = LegadoHostServices(executionContext: executionContext)
        super.init()
    }

    func invoke(_ payload: JSValue) -> Any {
        let dictionary = Self.stringDictionary(payload.toDictionary())
        let method = RuleExecutionContext.bridgeString(dictionary["method"])
        let arguments = Self.arguments(dictionary["args"])

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
            let url = arguments.count > 1
                ? RuleExecutionContext.bridgeString(arguments[0])
                : executionContext.string(for: "baseUrl")
            let cookie = RuleExecutionContext.bridgeString(arguments.count > 1 ? arguments[1] : arguments.first)
            return services.setCookie(url: url, value: cookie)
        case "getCookie":
            let url = arguments.first.map(RuleExecutionContext.bridgeString) ?? executionContext.string(for: "baseUrl")
            let key = arguments.count > 1 ? RuleExecutionContext.bridgeString(arguments[1]) : nil
            return services.cookie(url: url, key: key)
        case "log":
            let message = RuleExecutionContext.bridgeString(arguments.first)
            executionContext.log(message)
            return message
        case "ajaxAll":
            let urls: [String]
            if let values = arguments.first as? NSArray {
                urls = values.map { RuleExecutionContext.bridgeString($0) }
            } else {
                urls = arguments.map { RuleExecutionContext.bridgeString($0) }
            }
            return urls.map { executionContext.networkHandler?($0) ?? "" } as NSArray
        case "downloadFile":
            guard arguments.count >= 2 else { return "" }
            return services.downloadFile(
                RuleExecutionContext.bridgeString(arguments[0]),
                path: RuleExecutionContext.bridgeString(arguments[1])
            )
        case "unzipFile":
            return services.unzipFile(RuleExecutionContext.bridgeString(arguments.first))
        case "getTxtInFolder":
            return services.textFiles(in: RuleExecutionContext.bridgeString(arguments.first))
        case "readFile":
            return services.readFile(RuleExecutionContext.bridgeString(arguments.first))
        case "readTxtFile":
            return services.readText(
                RuleExecutionContext.bridgeString(arguments.first),
                charset: arguments.count > 1 ? RuleExecutionContext.bridgeString(arguments[1]) : nil
            )
        case "getZipStringContent":
            guard arguments.count >= 2 else { return "" }
            return services.zipString(
                zipPath: RuleExecutionContext.bridgeString(arguments[0]),
                entryName: RuleExecutionContext.bridgeString(arguments[1]),
                charset: arguments.count > 2 ? RuleExecutionContext.bridgeString(arguments[2]) : nil
            )
        case "getZipByteArrayContent":
            guard arguments.count >= 2,
                  let data = services.zipData(
                    zipPath: RuleExecutionContext.bridgeString(arguments[0]),
                    entryName: RuleExecutionContext.bridgeString(arguments[1])
                  ) else { return [] as NSArray }
            return data.map { NSNumber(value: $0) } as NSArray
        case "utf8ToGbk":
            return services.utf8ToGbk(RuleExecutionContext.bridgeString(arguments.first))
        case "encodeURI":
            return services.encodeURI(
                RuleExecutionContext.bridgeString(arguments.first),
                charset: arguments.count > 1 ? RuleExecutionContext.bridgeString(arguments[1]) : nil
            )
        case "htmlFormat":
            return services.htmlFormat(RuleExecutionContext.bridgeString(arguments.first))
        case "aesDecodeToByteArray", "aesDecodeToString", "aesBase64DecodeToByteArray",
             "aesBase64DecodeToString", "aesEncodeToByteArray", "aesEncodeToString",
             "aesEncodeToBase64ByteArray", "aesEncodeToBase64String":
            return services.aes(
                operation: method,
                input: arguments.first,
                key: arguments.count > 1 ? arguments[1] : nil,
                transformation: arguments.count > 2 ? RuleExecutionContext.bridgeString(arguments[2]) : "AES/CBC/PKCS7Padding",
                iv: arguments.count > 3 ? arguments[3] : nil
            )
        case "sandboxPath":
            return services.sandboxURL.path
        default:
            return ""
        }
    }

    private static func stringDictionary(_ value: [AnyHashable: Any]?) -> [String: Any] {
        guard let value else { return [:] }
        return value.reduce(into: [:]) { result, pair in
            result[String(describing: pair.key)] = pair.value
        }
    }

    private static func arguments(_ value: Any?) -> [Any] {
        if let value = value as? [Any] { return value }
        if let value = value as? NSArray { return value.map { $0 } }
        return value.map { [$0] } ?? []
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
        let dictionary = payload.toDictionary()?.reduce(into: [String: Any]()) {
            $0[String(describing: $1.key)] = $1.value
        } ?? [:]
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
    func tagName() -> String
    func tagName(_ value: String) -> LegadoElementBridge
    func id() -> String
    func isBlock() -> Bool
    func child(_ index: Int) -> LegadoElementBridge?
    func select(_ selector: String) -> LegadoElementsBridge
    func `is`(_ selector: String) -> Bool
    func text() -> String
    func text(_ value: String) -> LegadoElementBridge
    func ownText() -> String
    func hasText() -> Bool
    func data() -> String
    func html() -> String
    func html(_ value: String) -> LegadoElementBridge
    func outerHtml() -> String
    func attr(_ name: String) -> String
    func attr(_ name: String, _ value: String) -> LegadoElementsBridge
    func hasAttr(_ name: String) -> Bool
    func removeAttr(_ name: String) -> LegadoElementsBridge
    func addClass(_ name: String) -> LegadoElementsBridge
    func removeClass(_ name: String) -> LegadoElementsBridge
    func toggleClass(_ name: String) -> LegadoElementsBridge
    func hasClass(_ name: String) -> Bool
    func val() -> String
    func setVal(_ value: String) -> LegadoElementsBridge
    func hasText() -> Bool
    func prepend(_ html: String) -> LegadoElementsBridge
    func append(_ html: String) -> LegadoElementsBridge
    func before(_ html: String) -> LegadoElementsBridge
    func after(_ html: String) -> LegadoElementsBridge
    func wrap(_ html: String) -> LegadoElementsBridge
    func unwrap() -> LegadoElementsBridge
    func empty() -> LegadoElementsBridge
    func not(_ selector: String) -> LegadoElementsBridge
    func `is`(_ selector: String) -> Bool
    func attr(_ name: String, _ value: String) -> LegadoElementBridge
    func absUrl(_ name: String) -> String
    func hasAttr(_ name: String) -> Bool
    func removeAttr(_ name: String) -> LegadoElementBridge
    func parent() -> LegadoElementBridge?
    func parents() -> LegadoElementsBridge
    func children() -> LegadoElementsBridge
    func append(_ html: String) -> LegadoElementBridge
    func prepend(_ html: String) -> LegadoElementBridge
    func appendElement(_ tag: String) -> LegadoElementBridge
    func prependElement(_ tag: String) -> LegadoElementBridge
    func appendText(_ text: String) -> LegadoElementBridge
    func prependText(_ text: String) -> LegadoElementBridge
    func empty() -> LegadoElementBridge
    func cssSelector() -> String
    func siblingElements() -> LegadoElementsBridge
    func nextElementSibling() -> LegadoElementBridge?
    func previousElementSibling() -> LegadoElementBridge?
    func elementSiblingIndex() -> Int
    func getElementsByTag(_ tag: String) -> LegadoElementsBridge
    func getElementById(_ id: String) -> LegadoElementBridge?
    func getElementsByClass(_ name: String) -> LegadoElementsBridge
    func getElementsByAttribute(_ name: String) -> LegadoElementsBridge
    func className() -> String
    func classNames() -> NSArray
    func hasClass(_ name: String) -> Bool
    func addClass(_ name: String) -> LegadoElementBridge
    func removeClass(_ name: String) -> LegadoElementBridge
    func toggleClass(_ name: String) -> LegadoElementBridge
    func val() -> String
    func setVal(_ value: String) -> LegadoElementBridge
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

    func tagName() -> String { element.tagName() }
    func tagName(_ value: String) -> LegadoElementBridge { _ = try? element.tagName(value); return self }
    func id() -> String { (try? element.attr("id")) ?? "" }
    func isBlock() -> Bool { element.tag().isBlock() }
    func child(_ index: Int) -> LegadoElementBridge? {
        guard index >= 0, index < element.children().size() else { return nil }
        return LegadoElementBridge(element: element.child(index), baseURL: baseURL)
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

    func `is`(_ selector: String) -> Bool { (try? element.iS(selector)) ?? false }

    func text() -> String { (try? element.text()) ?? "" }
    func text(_ value: String) -> LegadoElementBridge { _ = try? element.text(value); return self }
    func ownText() -> String { element.ownText() }
    func hasText() -> Bool { element.hasText() }
    func data() -> String { element.data() }
    func html() -> String { (try? element.html()) ?? "" }
    func html(_ value: String) -> LegadoElementBridge { _ = try? element.html(value); return self }
    func outerHtml() -> String { (try? element.outerHtml()) ?? "" }
    func attr(_ name: String) -> String {
        if ["href", "src", "data-src"].contains(name.lowercased()),
           let absolute = try? element.absUrl(name),
           !absolute.isEmpty {
            return absolute
        }
        return (try? element.attr(name)) ?? ""
    }
    func attr(_ name: String, _ value: String) -> LegadoElementBridge { _ = try? element.attr(name, value); return self }
    func absUrl(_ name: String) -> String { (try? element.absUrl(name)) ?? "" }
    func hasAttr(_ name: String) -> Bool { element.hasAttr(name) }
    func removeAttr(_ name: String) -> LegadoElementBridge { _ = try? element.removeAttr(name); return self }

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

    func append(_ html: String) -> LegadoElementBridge { _ = try? element.append(html); return self }
    func prepend(_ html: String) -> LegadoElementBridge { _ = try? element.prepend(html); return self }
    func appendElement(_ tag: String) -> LegadoElementBridge {
        guard let child = try? element.appendElement(tag) else { return self }
        return LegadoElementBridge(element: child, baseURL: baseURL)
    }
    func prependElement(_ tag: String) -> LegadoElementBridge {
        guard let child = try? element.prependElement(tag) else { return self }
        return LegadoElementBridge(element: child, baseURL: baseURL)
    }
    func appendText(_ text: String) -> LegadoElementBridge { _ = try? element.appendText(text); return self }
    func prependText(_ text: String) -> LegadoElementBridge { _ = try? element.prependText(text); return self }
    func empty() -> LegadoElementBridge { _ = element.empty(); return self }
    func cssSelector() -> String { (try? element.cssSelector()) ?? "" }
    func siblingElements() -> LegadoElementsBridge {
        LegadoElementsBridge(elements: Array(element.siblingElements()), baseURL: baseURL)
    }
    func nextElementSibling() -> LegadoElementBridge? {
        guard let optional = try? element.nextElementSibling(), let value = optional else { return nil }
        return LegadoElementBridge(element: value, baseURL: baseURL)
    }
    func previousElementSibling() -> LegadoElementBridge? {
        guard let optional = try? element.previousElementSibling(), let value = optional else { return nil }
        return LegadoElementBridge(element: value, baseURL: baseURL)
    }
    func elementSiblingIndex() -> Int { (try? element.elementSiblingIndex()) ?? -1 }
    func getElementsByTag(_ tag: String) -> LegadoElementsBridge { wrap(try? element.getElementsByTag(tag)) }
    func getElementById(_ id: String) -> LegadoElementBridge? {
        guard let optional = try? element.getElementById(id), let value = optional else { return nil }
        return LegadoElementBridge(element: value, baseURL: baseURL)
    }
    func getElementsByClass(_ name: String) -> LegadoElementsBridge { wrap(try? element.getElementsByClass(name)) }
    func getElementsByAttribute(_ name: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttribute(name)) }
    func className() -> String { (try? element.className()) ?? "" }
    func classNames() -> NSArray { ((try? element.classNames().map { $0 }) ?? []) as NSArray }
    func hasClass(_ name: String) -> Bool { element.hasClass(name) }
    func addClass(_ name: String) -> LegadoElementBridge { _ = try? element.addClass(name); return self }
    func removeClass(_ name: String) -> LegadoElementBridge { _ = try? element.removeClass(name); return self }
    func toggleClass(_ name: String) -> LegadoElementBridge { _ = try? element.toggleClass(name); return self }
    func val() -> String { (try? element.val()) ?? "" }
    func setVal(_ value: String) -> LegadoElementBridge { _ = try? element.val(value); return self }

    private func wrap(_ values: SwiftSoup.Elements?) -> LegadoElementsBridge {
        LegadoElementsBridge(elements: values.map(Array.init) ?? [], baseURL: baseURL)
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
    func attr(_ name: String, _ value: String) -> LegadoElementsBridge
    func hasAttr(_ name: String) -> Bool
    func removeAttr(_ name: String) -> LegadoElementsBridge
    func addClass(_ name: String) -> LegadoElementsBridge
    func removeClass(_ name: String) -> LegadoElementsBridge
    func toggleClass(_ name: String) -> LegadoElementsBridge
    func hasClass(_ name: String) -> Bool
    func val() -> String
    func setVal(_ value: String) -> LegadoElementsBridge
    func hasText() -> Bool
    func prepend(_ html: String) -> LegadoElementsBridge
    func append(_ html: String) -> LegadoElementsBridge
    func before(_ html: String) -> LegadoElementsBridge
    func after(_ html: String) -> LegadoElementsBridge
    func wrap(_ html: String) -> LegadoElementsBridge
    func unwrap() -> LegadoElementsBridge
    func empty() -> LegadoElementsBridge
    func not(_ selector: String) -> LegadoElementsBridge
    func `is`(_ selector: String) -> Bool
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
    func attr(_ name: String, _ value: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.attr(name, value) }; return self }
    func hasAttr(_ name: String) -> Bool { elements.contains { $0.hasAttr(name) } }
    func removeAttr(_ name: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.removeAttr(name) }; return self }
    func addClass(_ name: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.addClass(name) }; return self }
    func removeClass(_ name: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.removeClass(name) }; return self }
    func toggleClass(_ name: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.toggleClass(name) }; return self }
    func hasClass(_ name: String) -> Bool { elements.contains { $0.hasClass(name) } }
    func val() -> String { elements.first.flatMap { try? $0.val() } ?? "" }
    func setVal(_ value: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.val(value) }; return self }
    func hasText() -> Bool { elements.contains { $0.hasText() } }
    func prepend(_ html: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.prepend(html) }; return self }
    func append(_ html: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.append(html) }; return self }
    func before(_ html: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.before(html) }; return self }
    func after(_ html: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.after(html) }; return self }
    func wrap(_ html: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.wrap(html) }; return self }
    func unwrap() -> LegadoElementsBridge { elements.forEach { _ = try? $0.unwrap() }; return self }
    func empty() -> LegadoElementsBridge { elements.forEach { _ = $0.empty() }; return self }
    func not(_ selector: String) -> LegadoElementsBridge {
        let values = elements.filter { !((try? $0.iS(normalizedSelector(selector))) ?? false) }
        return LegadoElementsBridge(elements: values, baseURL: baseURL)
    }
    func `is`(_ selector: String) -> Bool { elements.contains { (try? $0.iS(normalizedSelector(selector))) ?? false } }
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
