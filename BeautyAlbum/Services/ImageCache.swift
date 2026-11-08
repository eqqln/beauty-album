import Foundation
import SwiftUI
import UIKit

/// 缩略图内存缓存。相册网格同步读盘会掉帧，这里统一异步解码 + 缓存。
final class ImageCache {
    static let shared = ImageCache()

    private let cache = NSCache<NSString, UIImage>()
    private let queue = DispatchQueue(label: "beauty.imagecache", qos: .userInitiated, attributes: .concurrent)

    private init() {
        cache.countLimit = 400
        cache.totalCostLimit = 220 * 1024 * 1024
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            self?.cache.removeAllObjects()
        }
    }

    func cached(_ url: URL) -> UIImage? {
        cache.object(forKey: url.path as NSString)
    }

    func remove(_ url: URL) {
        cache.removeObject(forKey: url.path as NSString)
    }

    func removeAll() {
        cache.removeAllObjects()
    }

    func load(_ url: URL, completion: @escaping (UIImage?) -> Void) {
        if let hit = cached(url) {
            completion(hit)
            return
        }
        queue.async { [weak self] in
            let image = UIImage(contentsOfFile: url.path)
            if let image {
                let cost = Int(image.size.width * image.size.height * 4)
                self?.cache.setObject(image, forKey: url.path as NSString, cost: cost)
            }
            DispatchQueue.main.async { completion(image) }
        }
    }
}

/// 本地图片视图：占位 + 异步加载 + 淡入
struct LocalImage: View {
    let url: URL?
    var contentMode: ContentMode = .fill
    var placeholderIcon: String = "photo"

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
                    .transition(.opacity)
            } else {
                Rectangle()
                    .fill(Theme.placeholder)
                    .overlay(
                        Image(systemName: placeholderIcon)
                            .font(.system(size: 22, weight: .light))
                            .foregroundColor(Theme.muted)
                    )
            }
        }
        .task(id: url) {
            guard let url else { image = nil; return }
            if let hit = ImageCache.shared.cached(url) {
                image = hit
                return
            }
            image = nil
            ImageCache.shared.load(url) { loaded in
                withAnimation(.easeOut(duration: 0.18)) { image = loaded }
            }
        }
    }
}
