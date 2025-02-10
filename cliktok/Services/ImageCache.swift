import SwiftUI

actor ImageCache {
    static let shared = ImageCache()
    
    private let memoryCache = NSCache<NSString, UIImage>()
    private var loadingTasks: [String: Task<UIImage?, Error>] = [:]
    private let fileManager = FileManager.default
    private let diskCacheURL: URL
    
    private init() {
        // Configure memory cache limits (10MB)
        memoryCache.totalCostLimit = 10 * 1024 * 1024
        memoryCache.countLimit = 100
        
        // Setup disk cache
        let cacheURL = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        diskCacheURL = cacheURL.appendingPathComponent("ImageCache")
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }
    
    private func diskCacheURL(for url: URL) -> URL {
        let filename = url.absoluteString.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? url.lastPathComponent
        return diskCacheURL.appendingPathComponent(filename)
    }
    
    func image(for url: URL) async throws -> UIImage? {
        let key = url.absoluteString as NSString
        
        // Check memory cache first
        if let cachedImage = memoryCache.object(forKey: key) {
            print("ImageCache: Memory cache hit for \(url.lastPathComponent)")
            return cachedImage
        }
        
        // Check disk cache
        let diskURL = diskCacheURL(for: url)
        if let diskCachedImage = await loadImageFromDisk(url: diskURL) {
            print("ImageCache: Disk cache hit for \(url.lastPathComponent)")
            memoryCache.setObject(diskCachedImage, forKey: key)
            return diskCachedImage
        }
        
        // Check if there's already a loading task
        if let existingTask = loadingTasks[url.absoluteString] {
            print("ImageCache: Using existing loading task for \(url.lastPathComponent)")
            return try await existingTask.value
        }
        
        // Create new loading task
        let task = Task<UIImage?, Error> {
            print("ImageCache: Loading image from \(url.lastPathComponent)")
            
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad)
            let (data, _) = try await URLSession.shared.data(for: request)
            
            guard let image = UIImage(data: data) else {
                print("ImageCache: Failed to create image from data for \(url.lastPathComponent)")
                return nil
            }
            
            // Save to disk cache
            try? await saveToDisk(image: image, url: diskURL)
            
            // Cache in memory
            let cost = data.count
            memoryCache.setObject(image, forKey: key, cost: cost)
            print("ImageCache: Cached image for \(url.lastPathComponent) with cost \(cost) bytes")
            return image
        }
        
        loadingTasks[url.absoluteString] = task
        
        do {
            let image = try await task.value
            loadingTasks[url.absoluteString] = nil
            return image
        } catch {
            loadingTasks[url.absoluteString] = nil
            throw error
        }
    }
    
    private func loadImageFromDisk(url: URL) async -> UIImage? {
        guard let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        return image
    }
    
    private func saveToDisk(image: UIImage, url: URL) async throws {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        try data.write(to: url)
    }
    
    func prefetchImages(_ urls: [URL]) {
        for url in urls {
            Task {
                try? await image(for: url)
            }
        }
    }
    
    func clearCache() {
        memoryCache.removeAllObjects()
        loadingTasks.values.forEach { $0.cancel() }
        loadingTasks.removeAll()
        
        // Clear disk cache
        try? fileManager.removeItem(at: diskCacheURL)
        try? fileManager.createDirectory(at: diskCacheURL, withIntermediateDirectories: true)
    }
}

// SwiftUI Image extension for cached async loading
extension Image {
    static func cached(_ url: URL) async throws -> Image? {
        if let image = try await ImageCache.shared.image(for: url) {
            return Image(uiImage: image)
        }
        return nil
    }
} 