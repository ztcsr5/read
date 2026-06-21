import SwiftUI

struct SearchBookRow: View {
    let book: SearchBook

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            cover

            VStack(alignment: .leading, spacing: 6) {
                Text(book.name)
                    .font(.title3.bold())
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                Text(book.author ?? "作者未知")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(book.sourceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.blue)
                    .lineLimit(1)

                Text(book.bookUrl)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            Image(systemName: "plus.circle")
                .font(.title2)
                .foregroundStyle(AppTheme.accent)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var cover: some View {
        if let coverUrl = book.coverUrl, let url = URL(string: coverUrl) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                default:
                    placeholder
                }
            }
            .frame(width: 74, height: 98)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        } else {
            placeholder
                .frame(width: 74, height: 98)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color.blue.opacity(0.12))
            .overlay {
                Image(systemName: "book")
                    .font(.title)
                    .foregroundStyle(.blue)
            }
    }
}
