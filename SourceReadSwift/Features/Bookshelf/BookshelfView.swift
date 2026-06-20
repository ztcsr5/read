import SwiftUI

struct BookshelfView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    PodcastSectionTitle(
                        title: "主页",
                        subtitle: "像 Podcasts 一样管理你的阅读流"
                    )

                    EmptyStateCard(
                        systemImage: "books.vertical",
                        title: "书架还是空的",
                        message: "先去发现页搜索一本书，后续这里会显示阅读进度和最近章节。"
                    )
                }
                .padding(AppTheme.pagePadding)
            }
            .pageBackground()
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
