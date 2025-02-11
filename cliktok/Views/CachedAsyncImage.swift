import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    private let url: URL
    private let scale: CGFloat
    private let content: (Image) -> Content
    private let placeholder: () -> Placeholder
    
    @State private var image: UIImage?
    @State private var isLoading = false
    @State private var error: Error?
    
    init(
        url: URL,
        scale: CGFloat = 1.0,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = image {
                content(Image(uiImage: image))
            } else if isLoading {
                placeholder()
            } else if error != nil {
                placeholder()
            } else {
                placeholder()
                    .onAppear {
                        loadImage()
                    }
            }
        }
    }
    
    private func loadImage() {
        guard !isLoading else { return }
        
        isLoading = true
        
        Task {
            do {
                let loadedImage = try await ImageCacheManager.shared.loadImage(from: url)
                await MainActor.run {
                    self.image = loadedImage
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error
                    self.isLoading = false
                }
            }
        }
    }
}

// Convenience initializers
extension CachedAsyncImage {
    init(
        url: URL,
        scale: CGFloat = 1.0,
        content: @escaping (Image) -> Content
    ) where Placeholder == ProgressView<EmptyView, EmptyView> {
        self.init(url: url, scale: scale, content: content) {
            ProgressView()
        }
    }
    
    init(
        url: URL,
        scale: CGFloat = 1
    ) where Content == Image, Placeholder == ProgressView<EmptyView, EmptyView> {
        self.init(url: url, scale: scale, content: { $0 }) {
            ProgressView()
        }
    }
} 