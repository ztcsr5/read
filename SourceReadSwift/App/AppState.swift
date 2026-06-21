import Foundation
import Combine

@MainActor
final class AppState: ObservableObject {
    let sourceStore: SourceStore
    let bookshelfStore: BookshelfStore
    private let injectedEngine: SourceEngine?
    private var cancellables: Set<AnyCancellable> = []
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
        bookshelfStore: BookshelfStore? = nil,
        engine: SourceEngine? = nil
    ) {
        self.sourceStore = sourceStore ?? SourceStore()
        self.bookshelfStore = bookshelfStore ?? BookshelfStore()
        self.injectedEngine = engine
        bindChildStores()
    }

    func record(_ event: DiagnosticEvent) {
        diagnostics.insert(event, at: 0)
        if diagnostics.count > 200 {
            diagnostics.removeLast(diagnostics.count - 200)
        }
    }

    private func bindChildStores() {
        sourceStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)

        bookshelfStore.objectWillChange
            .sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    self?.objectWillChange.send()
                }
            }
            .store(in: &cancellables)
    }
}
