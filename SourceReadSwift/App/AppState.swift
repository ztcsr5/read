import Foundation

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    private let injectedEngine: SourceEngine?
    lazy var engine: SourceEngine = {
        if let injectedEngine {
            return injectedEngine
        }
        return LegadoSourceEngine(diagnostics: DiagnosticSink { event in
            Task { @MainActor [weak self] in
                self?.record(event)
            }
        })
    }()

    @Published var diagnostics: [DiagnosticEvent] = []

    init(
        sourceStore: SourceStore? = nil,
        engine: SourceEngine? = nil
    ) {
        self.sourceStore = sourceStore ?? SourceStore()
        self.injectedEngine = engine
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }
}
