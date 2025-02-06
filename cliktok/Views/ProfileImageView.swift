import SwiftUI

// Image Loader to handle caching
actor ImageLoader {
    static let shared = ImageLoader()
    
    private let cache: URLCache
    private var loadingTasks: [URL: Task<UIImage, Error>] = [:]
    
    private init() {
        // Create a 50MB cache for profile images
        let cacheSizeInBytes = 50 * 1024 * 1024
        self.cache = URLCache(memoryCapacity: cacheSizeInBytes / 2,
                            diskCapacity: cacheSizeInBytes,
                            diskPath: "profile_image_cache")
    }
    
    func loadImage(from url: URL) async throws -> UIImage {
        // Check if we're already loading this image
        if let existingTask = loadingTasks[url] {
            return try await existingTask.value
        }
        
        let task = Task {
            // Create URL request
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 30)
            
            // Check cache
            if let cachedResponse = cache.cachedResponse(for: request),
               let image = UIImage(data: cachedResponse.data) {
                return image
            }
            
            // Download and cache
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let image = UIImage(data: data) else {
                throw NSError(domain: "ImageLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid image data"])
            }
            
            // Store in cache
            cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
            
            return image
        }
        
        loadingTasks[url] = task
        
        // Clean up after loading
        defer {
            Task { await cleanupLoadingTask(for: url) }
        }
        
        return try await task.value
    }
    
    private func cleanupLoadingTask(for url: URL) {
        loadingTasks[url] = nil
    }
}

struct ProfileImageView: View {
    let imageURL: String?
    let size: CGFloat
    
    @State private var image: UIImage?
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if let image = image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(Color.white.opacity(0.2), lineWidth: 1))
            } else if isLoading {
                ProgressView()
                    .frame(width: size, height: size)
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .foregroundColor(.gray)
            }
        }
        .task(id: imageURL) {
            await loadImage()
        }
    }
    
    private func loadImage() async {
        guard let urlString = imageURL,
              let url = URL(string: urlString) else {
            return
        }
        
        isLoading = true
        
        do {
            let loadedImage = try await ImageLoader.shared.loadImage(from: url)
            await MainActor.run {
                self.image = loadedImage
                self.isLoading = false
            }
        } catch {
            print("Error loading profile image: \(error.localizedDescription)")
            await MainActor.run {
                self.isLoading = false
            }
        }
    }
}
