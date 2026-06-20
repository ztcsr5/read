import SwiftUI

struct SearchBookRow: View {
    let book: SearchBook

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.blue.opacity(0.12))
                .frame(width: 62, height: 82)
                .overlay {
                    Image(systemName: "book")
                        .font(.title2)
                        .foregroundStyle(.blue)
                }

            VStack(alignment: .leading, spacing: 6) {
                Text(book.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(book.author ?? "作者未知")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(book.sourceName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.accent)
                Text(book.bookUrl)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(.vertical, 8)
    }
}

