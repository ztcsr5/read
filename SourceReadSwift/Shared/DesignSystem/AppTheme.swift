import SwiftUI

enum AppTheme {
    static let background = Color(red: 0.96, green: 0.96, blue: 0.99)
    static let card = Color(.systemBackground)
    static let elevatedCard = Color(.secondarySystemGroupedBackground)
    static let accent = Color(red: 0.35, green: 0.31, blue: 0.86)
    static let secondaryText = Color.secondary

    static let cardRadius: CGFloat = 24
    static let pagePadding: CGFloat = 20
    static let capsuleRadius: CGFloat = 16
}

extension View {
    func pageBackground() -> some View {
        background(AppTheme.background.ignoresSafeArea())
    }

    func podcastCard() -> some View {
        padding(18)
            .background(AppTheme.card)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.cardRadius, style: .continuous))
            .shadow(color: .black.opacity(0.05), radius: 18, x: 0, y: 10)
    }
}

struct PodcastSectionTitle: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            if let subtitle {
                Text(subtitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
