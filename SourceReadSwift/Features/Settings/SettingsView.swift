import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        NavigationStack {
            List {
                Section("书源") {
                    NavigationLink {
                        SourceManagerView()
                    } label: {
                        Label("书源管理", systemImage: "tray.full")
                    }
                }

                Section("原生重写状态") {
                    LabeledContent("UI", value: "SwiftUI")
                    LabeledContent("核心", value: "LegadoCore V2")
                    LabeledContent("书源范围", value: "小说")
                }

                Section("最近诊断") {
                    if appState.diagnostics.isEmpty {
                        Text("暂无诊断")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.diagnostics) { event in
                            VStack(alignment: .leading, spacing: 4) {
                                Text("[\(event.stage)] \(event.message)")
                                    .font(.subheadline.weight(.semibold))
                                if let sourceName = event.sourceName {
                                    Text(sourceName)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                ForEach(event.details.sorted(by: { $0.key < $1.key }), id: \.key) { item in
                                    Text("\(item.key): \(item.value)")
                                        .font(.caption2)
                                        .lineLimit(2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("设置")
        }
    }
}
