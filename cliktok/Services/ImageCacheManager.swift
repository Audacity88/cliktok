import Foundation
import UIKit

final class ImageCacheManager {
    static let shared = ImageCacheManager()
    
    private let cache: NSCache<NSString, UIImage>
    private let memoryWarningNotifier = NotificationCenter.default
    private let queue = DispatchQueue(label: "com.cliktok.imagecache")
    
    // Maximum number of images to keep in memory
    private let maxCacheSize = 100
    // Maximum memory usage in bytes (50MB)
    private let maxMemoryUsage: Int = 50 * 1024 * 1024
    
    private init() {
        cache = NSCache<NSString, UIImage>()
        cache.countLimit = maxCacheSize
        cache.totalCostLimit = maxMemoryUsage
        
        // Clear cache on memory warning
        memoryWarningNotifier.addObserver(
            self,
            selector: #selector(clearCache),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }
    
    deinit {
        memoryWarningNotifier.removeObserver(self)
    }
    
    func cacheImage(_ image: UIImage, forKey key: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            // Estimate memory size of image
            let cost = Int(image.size.width * image.size.height * 4) // 4 bytes per pixel
            self.cache.setObject(image, forKey: key as NSString, cost: cost)
        }
    }
    
    func getCachedImage(forKey key: String) -> UIImage? {
        queue.sync { [weak self] in
            return self?.cache.object(forKey: key as NSString)
        }
    }
    
    @objc func clearCache() {
        queue.async { [weak self] in
            self?.cache.removeAllObjects()
        }
    }
    
    func removeCachedImage(forKey key: String) {
        queue.async { [weak self] in
            self?.cache.removeObject(forKey: key as NSString)
        }
    }
    
    var cachedImagesCount: Int {
        return cache.totalCostLimit
    }
    
    var estimatedMemoryUsage: Int {
        return cache.totalCostLimit
    }
}

// MARK: - SwiftUI Image Loading Extension
extension ImageCacheManager {
    func loadImage(from url: URL) async throws -> UIImage {
        let key = url.absoluteString
        
        // Check cache first
        if let cachedImage = getCachedImage(forKey: key) {
            return cachedImage
        }
        
        // Load image from URL
        let (data, _) = try await URLSession.shared.data(from: url)
        guard let image = UIImage(data: data) else {
            throw URLError(.cannotDecodeContentData)
        }
        
        // Cache the loaded image
        cacheImage(image, forKey: key)
        return image
    }
} 