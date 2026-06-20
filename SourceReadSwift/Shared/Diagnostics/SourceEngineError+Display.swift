import Foundation

extension SourceEngineError {
    var displayMessage: String {
        switch self {
        case .unsupported(let text), .invalidSource(let text), .network(let text),
             .rule(let text), .javascript(let text), .blocked(let text), .empty(let text):
            return text
        }
    }
}

