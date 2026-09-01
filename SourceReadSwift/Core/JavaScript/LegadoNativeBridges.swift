import Foundation
import JavaScriptCore
import SwiftSoup

@objc protocol LegadoTagExport: JSExport {
    func getName() -> String
    func getNameNormal() -> String
    func isBlock() -> Bool
    func formatAsBlock() -> Bool
    func canContainBlock() -> Bool
    func isInline() -> Bool
    func isData() -> Bool
    func isEmpty() -> Bool
    func isSelfClosing() -> Bool
    func isKnownTag() -> Bool
    func preserveWhitespace() -> Bool
}

@objc protocol LegadoAttributeExport: JSExport {
    func getKey() -> String; func setKey(_ value: String) -> LegadoAttributeBridge
    func getValue() -> String; func setValue(_ value: String) -> LegadoAttributeBridge
    func html() -> String; func toString() -> String; func isDataAttribute() -> Bool; func isBooleanAttribute() -> Bool
}

final class LegadoAttributeBridge: NSObject, LegadoAttributeExport {
    fileprivate var key: String; fileprivate var value: String
    init(key: String, value: String) { self.key = key; self.value = value; super.init() }
    func getKey() -> String { key }; func setKey(_ value: String) -> LegadoAttributeBridge { key = value; return self }
    func getValue() -> String { value }; func setValue(_ value: String) -> LegadoAttributeBridge { self.value = value; return self }
    func html() -> String { "\(key)=\"\(value)\"" }; func toString() -> String { html() }
    func isDataAttribute() -> Bool { key.lowercased().hasPrefix("data-") }
    func isBooleanAttribute() -> Bool { ["disabled","checked","selected","readonly","multiple","required"].contains(key.lowercased()) }
}

@objc protocol LegadoAttributesExport: JSExport {
    func get(_ key: String) -> String; func getIgnoreCase(_ key: String) -> String
    func put(_ key: String, _ value: String); func remove(_ key: String); func removeIgnoreCase(_ key: String)
    func hasKey(_ key: String) -> Bool; func hasKeyIgnoreCase(_ key: String) -> Bool; func size() -> Int
    func asList() -> NSArray; func dataset() -> NSDictionary; func html() -> String; func toString() -> String
}

final class LegadoAttributesBridge: NSObject, LegadoAttributesExport {
    fileprivate let attributes: Attributes
    init(attributes: Attributes) { self.attributes = attributes; super.init() }
    func get(_ key: String) -> String { attributes.get(key: key) }
    func getIgnoreCase(_ key: String) -> String { (try? attributes.getIgnoreCase(key: key)) ?? "" }
    func put(_ key: String, _ value: String) { try? attributes.put(key, value) }
    func remove(_ key: String) { try? attributes.remove(key: key) }
    func removeIgnoreCase(_ key: String) { try? attributes.removeIgnoreCase(key: key.utf8Array) }
    func hasKey(_ key: String) -> Bool { attributes.hasKey(key: key) }
    func hasKeyIgnoreCase(_ key: String) -> Bool { attributes.hasKeyIgnoreCase(key: key) }
    func size() -> Int { attributes.size() }
    func asList() -> NSArray { attributes.asList().map { LegadoAttributeBridge(key: $0.getKey(), value: $0.getValue()) } as NSArray }
    func dataset() -> NSDictionary { attributes.dataset() as NSDictionary }
    func html() -> String { (try? attributes.html()) ?? "" }; func toString() -> String { html() }
}

@objc protocol LegadoNodeExport: JSExport {
    func nodeName() -> String
    func getAttributes() -> LegadoAttributesBridge
    func getWholeData() -> String
    func setWholeData(_ value: String) -> LegadoNodeBridge
    func getWholeText() -> String
    func text(_ value: String) -> LegadoNodeBridge
    func isBlank() -> Bool
    func toString() -> String
}

class LegadoNodeBridge: NSObject, LegadoNodeExport {
    fileprivate let node: SwiftSoup.Node
    init(node: SwiftSoup.Node) { self.node = node; super.init() }
    func nodeName() -> String { node.nodeName() }
    func getWholeData() -> String { (node as? DataNode)?.getWholeData() ?? "" }
    func setWholeData(_ value: String) -> LegadoNodeBridge { if let data = node as? DataNode { _ = try? data.setWholeData(value) }; return self }
    func getWholeText() -> String { (node as? TextNode)?.getWholeText() ?? "" }
    func text(_ value: String) -> LegadoNodeBridge { if let text = node as? TextNode { _ = text.text(value) }; return self }
    func isBlank() -> Bool { (node as? TextNode)?.isBlank() ?? false }
    func toString() -> String { (try? node.outerHtml()) ?? node.nodeName() }
}

private func bridgeNode(_ node: SwiftSoup.Node) -> NSObject {
    if let element = node as? SwiftSoup.Element {
        return LegadoElementBridge(element: element, baseURL: element.getBaseUri())
    }
    return LegadoNodeBridge(node: node)
}

final class LegadoTagBridge: NSObject, LegadoTagExport {
    private let name: String
    init(tagName: String) { self.name = tagName; super.init() }
    func getName() -> String { name }
    func getNameNormal() -> String { name.lowercased() }
    func isBlock() -> Bool { ["html","head","body","div","p","ul","ol","li","table","tr","td","section","article","header","footer"].contains(name.lowercased()) }
    func formatAsBlock() -> Bool { isBlock() }
    func canContainBlock() -> Bool { isBlock() }
    func isInline() -> Bool { !isBlock() }
    func isData() -> Bool { ["script","style"].contains(name.lowercased()) }
    func isEmpty() -> Bool { ["br","img","meta","link","input","hr"].contains(name.lowercased()) }
    func isSelfClosing() -> Bool { isEmpty() }
    func isKnownTag() -> Bool { !name.isEmpty }
    func preserveWhitespace() -> Bool { ["pre","textarea","script","style"].contains(name.lowercased()) }
}

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
    func nodeName() -> String
    func nodeAttr(_ name: String) -> String
    func nodeAttr(_ name: String, _ value: String) -> LegadoElementBridge
    func nodeHasAttr(_ name: String) -> Bool
    func nodeRemoveAttr(_ name: String) -> LegadoElementBridge
    func getBaseUri() -> String
    func setBaseUri(_ value: String) -> LegadoElementBridge
    func nodeAbsUrl(_ name: String) -> String
    func childNode(_ index: Int) -> LegadoElementBridge?
    func getChildNodes() -> NSArray
    func childNodesCopy() -> NSArray
    func childNodeSize() -> Int
    func ownerDocument() -> LegadoElementBridge?
    func before(_ html: String) -> LegadoElementBridge
    func after(_ html: String) -> LegadoElementBridge
    func wrap(_ html: String) -> LegadoElementBridge
    func unwrap() -> LegadoElementBridge
    func replaceWith(_ html: String) -> LegadoElementBridge
    func setParentNode(_ parent: LegadoElementBridge?) -> LegadoElementBridge
    func replaceChild(_ oldIndex: Int, _ html: String) -> LegadoElementBridge
    func removeChild(_ index: Int) -> LegadoElementBridge
    func addChildren(_ html: String) -> LegadoElementBridge
    func addChildrenAt(_ index: Int, _ html: String) -> LegadoElementBridge
    func siblingNodes() -> NSArray
    func nextSibling() -> LegadoElementBridge?
    func previousSibling() -> LegadoElementBridge?
    func setSiblingIndex(_ index: Int) -> LegadoElementBridge
    func nodeOuterHtml() -> String
    func nodeHtml(_ value: String) -> LegadoElementBridge
    func equalsNode(_ other: LegadoElementBridge?) -> Bool
    func hasSameValue(_ other: LegadoElementBridge?) -> Bool
    func location() -> String
    func head() -> LegadoElementBridge?
    func body() -> LegadoElementBridge?
    func title() -> String
    func title(_ value: String) -> LegadoElementBridge
    func createElement(_ tag: String) -> LegadoElementBridge?
    func normalise() -> LegadoElementBridge
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
    // Element mutators return the element itself (matching Jsoup's fluent API).
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
    func getElementsByAttributeStarting(_ prefix: String) -> LegadoElementsBridge
    func getElementsByAttributeValue(_ key: String, _ value: String) -> LegadoElementsBridge
    func getElementsByAttributeValueNot(_ key: String, _ value: String) -> LegadoElementsBridge
    func getElementsByAttributeValueStarting(_ key: String, _ value: String) -> LegadoElementsBridge
    func getElementsByAttributeValueEnding(_ key: String, _ value: String) -> LegadoElementsBridge
    func getElementsByAttributeValueContaining(_ key: String, _ value: String) -> LegadoElementsBridge
    func getElementsByAttributeValueMatching(_ key: String, _ value: String) -> LegadoElementsBridge
    func getElementsContainingText(_ value: String) -> LegadoElementsBridge
    func getElementsContainingOwnText(_ value: String) -> LegadoElementsBridge
    func getElementsMatchingText(_ value: String) -> LegadoElementsBridge
    func getElementsMatchingOwnText(_ value: String) -> LegadoElementsBridge
    func getAllElements() -> LegadoElementsBridge
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

    func before(_ html: String) -> LegadoElementBridge { _ = try? element.before(html); return self }
    func after(_ html: String) -> LegadoElementBridge { _ = try? element.after(html); return self }

    func nodeName() -> String { element.nodeName() }
    func getAttributes() -> LegadoAttributesBridge {
        if let attributes = element.getAttributes() { return LegadoAttributesBridge(attributes: attributes) }
        return LegadoAttributesBridge(attributes: Attributes())
    }
    func nodeAttr(_ name: String) -> String { (try? element.attr(name)) ?? "" }
    func nodeAttr(_ name: String, _ value: String) -> LegadoElementBridge { _ = try? element.attr(name, value); return self }
    func nodeHasAttr(_ name: String) -> Bool { element.hasAttr(name) }
    func nodeRemoveAttr(_ name: String) -> LegadoElementBridge { _ = try? element.removeAttr(name); return self }
    func getBaseUri() -> String { element.getBaseUri() }
    func setBaseUri(_ value: String) -> LegadoElementBridge { try? element.setBaseUri(value); return self }
    func nodeAbsUrl(_ name: String) -> String { (try? element.absUrl(name)) ?? "" }
    func childNode(_ index: Int) -> LegadoElementBridge? {
        guard index >= 0, index < element.childNodeSize(), let child = element.childNode(index) as? SwiftSoup.Element else { return nil }
        return LegadoElementBridge(element: child, baseURL: baseURL)
    }
    func getChildNodes() -> NSArray { element.getChildNodes().map { bridgeNode($0) } as NSArray }
    func childNodesCopy() -> NSArray { element.childNodesCopy().map { bridgeNode($0) } as NSArray }
    func childNodeSize() -> Int { element.childNodeSize() }
    func ownerDocument() -> LegadoElementBridge? {
        guard let document = element.ownerDocument() else { return nil }
        return LegadoElementBridge(element: document, baseURL: baseURL)
    }
    func wrap(_ html: String) -> LegadoElementBridge { _ = try? element.wrap(html); return self }
    func unwrap() -> LegadoElementBridge { _ = try? element.unwrap(); return self }
    func replaceWith(_ html: String) -> LegadoElementBridge {
        guard let parent = element.parent(), let nodes = try? Parser.parseFragment(html, parent, parent.getBaseUriUTF8()), let first = nodes.first else { return self }
        try? element.replaceWith(first)
        return self
    }
    func setParentNode(_ parent: LegadoElementBridge?) -> LegadoElementBridge { try? element.setParentNode(parent?.element); return self }
    func replaceChild(_ oldIndex: Int, _ html: String) -> LegadoElementBridge {
        guard oldIndex >= 0, oldIndex < element.childNodeSize(), let nodes = try? Parser.parseFragment(html, element, element.getBaseUriUTF8()), let first = nodes.first else { return self }
        try? element.replaceChild(element.childNode(oldIndex), first)
        return self
    }
    func removeChild(_ index: Int) -> LegadoElementBridge {
        guard index >= 0, index < element.childNodeSize() else { return self }
        try? element.removeChild(element.childNode(index)); return self
    }
    func addChildren(_ html: String) -> LegadoElementBridge {
        if let nodes = try? Parser.parseFragment(html, element, element.getBaseUriUTF8()) { try? element.addChildren(nodes) }; return self
    }
    func addChildrenAt(_ index: Int, _ html: String) -> LegadoElementBridge {
        if let nodes = try? Parser.parseFragment(html, element, element.getBaseUriUTF8()) { try? element.addChildren(index, nodes) }; return self
    }
    func siblingNodes() -> NSArray { element.siblingNodes().map { bridgeNode($0) } as NSArray }
    func nextSibling() -> LegadoElementBridge? { (element.nextSibling() as? SwiftSoup.Element).map { LegadoElementBridge(element: $0, baseURL: baseURL) } }
    func previousSibling() -> LegadoElementBridge? { (element.previousSibling() as? SwiftSoup.Element).map { LegadoElementBridge(element: $0, baseURL: baseURL) } }
    func setSiblingIndex(_ index: Int) -> LegadoElementBridge { element.setSiblingIndex(index); return self }
    func nodeOuterHtml() -> String { (try? element.outerHtml()) ?? "" }
    func nodeHtml(_ value: String) -> LegadoElementBridge { _ = try? element.html(value); return self }
    func equalsNode(_ other: LegadoElementBridge?) -> Bool { element === other?.element }
    func hasSameValue(_ other: LegadoElementBridge?) -> Bool {
        guard let other else { return false }
        return (try? element.hasSameValue(other.element)) ?? false
    }

    // Additional methods exposed by SourceRead's JsoupElementExport ABI.
    func tagNameNormal() -> String { element.tagNameNormal() }
    func tag() -> LegadoTagBridge { LegadoTagBridge(tagName: element.tagName()) }
    func dataset() -> NSDictionary { element.dataset() as NSDictionary }
    func textNodes() -> NSArray { element.textNodes() as NSArray }
    func dataNodes() -> NSArray { element.dataNodes() as NSArray }
    func insertChildren(_ index: Int, _ html: String) -> LegadoElementBridge {
        guard let nodes = try? Parser.parseFragment(html, element, element.getBaseUriUTF8()) else { return self }
        try? element.addChildren(index, nodes)
        return self
    }
    func getElementsByAttributeStarting(_ prefix: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeStarting(prefix)) }
    func getElementsByAttributeValue(_ key: String, _ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeValue(key, value)) }
    func getElementsByAttributeValueNot(_ key: String, _ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeValueNot(key, value)) }
    func getElementsByAttributeValueStarting(_ key: String, _ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeValueStarting(key, value)) }
    func getElementsByAttributeValueEnding(_ key: String, _ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeValueEnding(key, value)) }
    func getElementsByAttributeValueContaining(_ key: String, _ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeValueContaining(key, value)) }
    func getElementsByAttributeValueMatching(_ key: String, _ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsByAttributeValueMatching(key, value)) }
    func getElementsContainingText(_ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsContainingText(value)) }
    func getElementsContainingOwnText(_ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsContainingOwnText(value)) }
    func getElementsMatchingText(_ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsMatchingText(value)) }
    func getElementsMatchingOwnText(_ value: String) -> LegadoElementsBridge { wrap(try? element.getElementsMatchingOwnText(value)) }
    func getAllElements() -> LegadoElementsBridge { wrap(try? element.getAllElements()) }

    // JsoupDocumentExport methods. A Document is represented by the same wrapper,
    // so JavaScript can use document.head/body/title without a second object graph.
    func location() -> String { (element as? Document)?.location() ?? baseURL }
    func head() -> LegadoElementBridge? { (element as? Document)?.head().map { LegadoElementBridge(element: $0, baseURL: baseURL) } }
    func body() -> LegadoElementBridge? { (element as? Document)?.body().map { LegadoElementBridge(element: $0, baseURL: baseURL) } }
    func title() -> String {
        guard let document = element as? Document else { return "" }
        return (try? document.title()) ?? ""
    }
    func title(_ value: String) -> LegadoElementBridge {
        if let document = element as? Document { try? document.title(value) }
        return self
    }
    func createElement(_ tag: String) -> LegadoElementBridge? {
        guard let document = element as? Document, let child = try? document.createElement(tag) else { return nil }
        return LegadoElementBridge(element: child, baseURL: baseURL)
    }
    func normalise() -> LegadoElementBridge { if let document = element as? Document { _ = try? document.normalise() }; return self }
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
    func tagName(_ value: String) -> LegadoElementsBridge
    func add(_ element: LegadoElementBridge) -> LegadoElementsBridge
    func addAt(_ index: Int, _ element: LegadoElementBridge) -> LegadoElementsBridge
    func array() -> NSArray
    func toArray() -> NSArray
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

    func tagName(_ value: String) -> LegadoElementsBridge { elements.forEach { _ = try? $0.tagName(value) }; return self }
    func add(_ element: LegadoElementBridge) -> LegadoElementsBridge { elements.append(element.element); return self }
    func addAt(_ index: Int, _ element: LegadoElementBridge) -> LegadoElementsBridge {
        let i = max(0, min(index, elements.count)); elements.insert(element.element, at: i); return self
    }
    func array() -> NSArray { elements.map { LegadoElementBridge(element: $0, baseURL: baseURL) } as NSArray }
    func toArray() -> NSArray { array() }
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
