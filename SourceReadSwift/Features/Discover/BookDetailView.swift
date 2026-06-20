import SwiftUI

struct BookDetailView: View {
    let book: SearchBook

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                SearchBookRow(book: book)
                    .podcastCard()

                EmptyStateCard(
                    systemImage: "wrench.and.screwdriver",
                    title: "详情链路正在迁移",
                    message: "下一阶段由 Swift LegadoCore 接管详情、目录和正文，不再让页面无限 skeleton。"
                )
            }
            .padding(AppTheme.pagePadding)
        }
        .pageBackground()
        .navigationTitle(book.name)
        .navigationBarTitleDisplayMode(.inline)
    }
}
