import Foundation

struct DiagnosticSink: Sendable {
    let emit: @Sendable (DiagnosticEvent) async -> Void

    static let noop = DiagnosticSink { _ in }
}

