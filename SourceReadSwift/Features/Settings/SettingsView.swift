import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var themeMode: ThemeMode = .system
    @State private var cacheSize = "0.00 MB"
    @State private var showPlaceholderAlert = false

    var body: some View {
        NavigationStack {
            List {
                Section("外观") {
                    ForEach(ThemeMode.allCases) { mode in
                        Button {
                            themeMode = mode
                        } label: {
                            HStack {
                                Text(mode.title)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if themeMode == mode {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(AppTheme.accent)
                                }
                            }
                        }
                    }
                }

                Section("内容设置") {
                    NavigationLink {
                        SourceManagerView()
                    } label: {
                        Label("书源管理", systemImage: "square.stack.3d.up")
                    }

                    Button {
                        showPlaceholderAlert = true
                    } label: {
                        Label("规则净化", systemImage: "shield")
                    }
                }

                Section("通用") {
                    Button {
                        cacheSize = "0.00 MB"
                    } label: {
                        HStack {
                            Label("清理缓存", systemImage: "trash")
                            Spacer()
                            Text(cacheSize)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Button {
                        showPlaceholderAlert = true
                    } label: {
                        Label("阅读历史", systemImage: "clock")
                    }

                    Button {
                        showPlaceholderAlert = true
                    } label: {
                        Label("关于阅读", systemImage: "info.circle")
                    }
                }

                Section("最近诊断") {
                    if appState.diagnostics.isEmpty {
                        Text("暂无诊断")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(appState.diagnostics.prefix(12))) { event in
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
            .alert("功能正在恢复", isPresented: $showPlaceholderAlert) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("这里会按 Flutter 原版功能补齐；当前阶段先恢复主界面、发现页和书源基础链路。")
            }
        }
    }
}

private enum ThemeMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark
    case eyeCare

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色模式"
        case .dark: return "深色模式"
        case .eyeCare: return "护眼模式"
        }
    }
}
