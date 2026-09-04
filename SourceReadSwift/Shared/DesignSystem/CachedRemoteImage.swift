import SwiftUI
import UIKit

/// Lightweight in-memory image loader for scrolling lists. `AsyncImage` is
/// convenient but does not provide an app-wide memory cache, so revisiting a
/// bookshelf/search row can decode the same cover repeatedly. This loader
/// keeps decoded images in an NSCache and leaves disk/network caching to
/// URLSession.
struct CachedRemoteImage<Placeholder: View>: View {
    let url: URL?
    let contentMode: ContentMode
    let placeholder: () -> Placeholder

    @State private var image: UIImage?

    init(
        url: URL?,
        contentMode: ContentMode = .fill,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.contentMode = contentMode
        self.placeholder = placeholder
    }

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder()
            }
        }
        .task(id: url?.absoluteString ?? "") {
            await loadImage()
        }
    }

    private func loadImage() async {
        guard let url else {
            await MainActor.run { image = nil }
            return
        }
        if let cached = ImageMemoryCache.shared.image(for: url) {
            await MainActor.run { image = cached }
            return
        }

        do {
            var request = URLRequest(url: url)
            request.cachePolicy = .returnCacheDataElseLoad
            let (data, response) = try await URLSession.shared.data(for: request)
            guard !Task.isCancelled,
                  let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let decoded = UIImage(data: data) else { return }
            ImageMemoryCache.shared.insert(decoded, for: url)
            await MainActor.run { image = decoded }
        } catch {
            // Keep the placeholder; a failed cover must never block list
            // scrolling or trigger a state-update loop.
        }
    }
}

private final class ImageMemoryCache {
    static let shared = ImageMemoryCache()

    private let cache = NSCache<NSURL, UIImage>()

    private init() {
        cache.countLimit = 120
        cache.totalCostLimit = 48 * 1024 * 1024
    }

    func image(for url: URL) -> UIImage? {
        cache.object(forKey: url as NSURL)
    }

    func insert(_ image: UIImage, for url: URL) {
        let cost = Int(image.size.width * image.size.height * image.scale * image.scale * 4)
        cache.setObject(image, forKey: url as NSURL, cost: max(cost, 1))
    }
}
