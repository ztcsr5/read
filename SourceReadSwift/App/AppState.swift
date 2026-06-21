import Foundation

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    private(set) var engine: SourceEngine

    @Published var diagnostics: [DiagnosticEvent] = []

    init(
        sourceStore: SourceStore = SourceStore(),
        engine: SourceEngine? = nil
    ) {
        self.sourceStore = sourceStore
        self.engine = engine ?? LegadoSourceEngine()
        if engine == nil {
            self.engine = LegadoSourceEngine(diagnostics: DiagnosticSink { [weak self] event in
                await MainActor.run {
                    self?.record(event)
                }
            })
        }
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }
}
