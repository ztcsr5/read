import Foundation

enum DiagnosticLevel: String, Codable, Sendable {
    case info
    case warning
    case error
}

struct DiagnosticEvent: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let date: Date
    let level: DiagnosticLevel
    let stage: String
    let sourceName: String?
    let message: String
    let details: [String: String]

    init(
        id: UUID = UUID(),
        date: Date = Date(),
        level: DiagnosticLevel,
        stage: String,
        sourceName: String? = nil,
        message: String,
        details: [String: String] = [:]
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.stage = stage
        self.sourceName = sourceName
        self.message = message
        self.details = details
    }
}

enum SourceEngineError: Error, Equatable {
    case unsupported(String)
    case invalidSource(String)
    case network(String)
    case rule(String)
    case javascript(String)
    case blocked(String)
    case empty(String)
}

