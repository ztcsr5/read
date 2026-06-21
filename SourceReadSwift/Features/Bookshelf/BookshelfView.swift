import SwiftUI

struct BookshelfView: View {
    @State private var showImportUnavailable = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 34) {
                    PodcastLargeTitleBar(title: "主页") {
                        HStack(spacing: 18) {
                            Button {
                                showImportUnavailable = true
                            } label: {
                                Image(systemName: "folder.badge.plus")
                                    .font(.system(size: 30, weight: .semibold))
                                    .foregroundStyle(AppTheme.accent)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("导入本地书籍")

                            Button {
                                showImportUnavailable = true
                            } label: {
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 38, weight: .regular))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 44, height: 44)
                            }
                            .accessibilityLabel("个人中心")
                        }
                    }
                    .padding(.top, 18)

                    VStack(alignment: .leading, spacing: 6) {
                        PodcastChevronSectionHeader(title: "正在阅读")
                        CenterTextEmptyState("暂无阅读记录", minHeight: 300)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        PodcastChevronSectionHeader(title: "最新更新")
                        CenterTextEmptyState("暂无更新书籍", minHeight: 260)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        PodcastChevronSectionHeader(title: "书架")
                    }

                    Color.clear.frame(height: 110)
                }
                .padding(.horizontal, AppTheme.pagePadding)
            }
            .refreshable {}
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .alert("本地导入正在恢复", isPresented: $showImportUnavailable) {
                Button("知道了", role: .cancel) {}
            } message: {
                Text("当前阶段先恢复 Flutter 原版首页结构。下一阶段会接回文件导入、书架列表和阅读进度。")
            }
        }
    }
}
