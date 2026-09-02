import SwiftUI
import UIKit

struct SourceDiagnosticHistoryView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let source: BookSource

    var body: some View {
        NavigationStack {
            Group {
                if appState.sourceDiagnosticHistoryStore.records(for: source).isEmpty {
                    ContentUnavailableView("暂无诊断历史", systemImage: "clock.arrow.circlepath", description: Text("从书源测试页执行一次完整链路后，这里会保留最近记录。"))
                } else {
                    List {
                        Section {
                            Text(source.bookSourceName).font(.headline)
                            Text(source.bookSourceUrl).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        }
                        ForEach(appState.sourceDiagnosticHistoryStore.records(for: source)) { entry in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Image(systemName: entry.status.systemImage)
                                        .foregroundStyle(entry.status.color)
                                    Text(entry.stage.uppercased())
                                        .font(.caption.weight(.bold))
                                    Spacer()
                                    Text(entry.status.title)
                                        .font(.caption.weight(.bold))
                                        .foregroundStyle(entry.status.color)
                                }
                                Text(entry.message)
                                    .font(.subheadline)
                                    .lineLimit(3)
                                HStack(spacing: 10) {
                                    Text(entry.testedAt.formatted(date: .abbreviated, time: .shortened))
                                    if let elapsed = entry.elapsedMilliseconds { Text("\(elapsed) ms") }
                                    if entry.resultCount > 0 { Text("结果 \(entry.resultCount)") }
                                }
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("诊断历史")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        UIPasteboard.general.string = appState.sourceDiagnosticHistoryStore.exportText(for: source)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .disabled(appState.sourceDiagnosticHistoryStore.records(for: source).isEmpty)
                    .accessibilityLabel("复制诊断历史")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("清空", role: .destructive) {
                        appState.sourceDiagnosticHistoryStore.clear(for: source)
                    }
                    .disabled(appState.sourceDiagnosticHistoryStore.records(for: source).isEmpty)
                }
            }
        }
    }
}

private extension SourceHealthStatus {
    var title: String {
        switch self {
        case .passed: return "PASS"
        case .warning: return "WARN"
        case .failed: return "FAIL"
        case .requiresLogin: return "LOGIN"
        case .verificationRequired: return "VERIFY"
        case .blocked: return "BLOCKED"
        }
    }

    var systemImage: String {
        switch self {
        case .passed: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .failed: return "xmark.circle.fill"
        case .requiresLogin: return "person.crop.circle.badge.exclamationmark"
        case .verificationRequired: return "shield.lefthalf.filled.badge.exclamationmark"
        case .blocked: return "hand.raised.slash.fill"
        }
    }

    var color: Color {
        switch self {
        case .passed: return .green
        case .warning: return .orange
        case .failed: return .red
        case .requiresLogin: return .orange
        case .verificationRequired: return .purple
        case .blocked: return .red.opacity(0.8)
        }
    }
}
