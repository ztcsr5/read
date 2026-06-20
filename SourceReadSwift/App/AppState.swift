import Foundation

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    let engine: SourceEngine

    @Published var diagnostics: [DiagnosticEvent] = []

    init(
        sourceStore: SourceStore = SourceStore(),
        engine: SourceEngine = LegadoSourceEngine()
    ) {
        self.sourceStore = sourceStore
        self.engine = engine
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }
}

