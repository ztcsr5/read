import Foundation
import os

enum PerformanceSignpost {
    private static let log = OSLog(
        subsystem: "com.edc21.SourceReadSwift",
        category: "performance"
    )

    static func begin(_ name: StaticString) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
    }

    static func end(_ name: StaticString, id: OSSignpostID) {
        os_signpost(.end, log: log, name: name, signpostID: id)
    }

    static func event(_ name: StaticString, _ message: String) {
        os_signpost(.event, log: log, name: name, "%{public}s", message)
    }
}
