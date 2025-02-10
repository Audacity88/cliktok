import SwiftUI

struct CachedAsyncImage<Content: View, Placeholder: View>: View {
    let url: URL?
    let scale: CGFloat
    let animation: Animation?
    let content: (Image) -> Content
    let placeholder: () -> Placeholder
    
    @State private var cachedImage: Image? = nil
    @State private var isLoading = false
    
    init(
        url: URL?,
        scale: CGFloat = 1.0,
        animation: Animation? = .default,
        @ViewBuilder content: @escaping (Image) -> Content,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.url = url
        self.scale = scale
        self.animation = animation
        self.content = content
        self.placeholder = placeholder
    }
    
    var body: some View {
        Group {
            if let image = cachedImage {
                content(image)
            } else {
                placeholder()
                    .task(id: url) {
                        await loadImage()
                    }
            }
        }
    }
    
    private func loadImage() async {
        guard !isLoading, let url = url else { return }
        isLoading = true
        defer { isLoading = false }
        
        do {
            if let image = try await Image.cached(url) {
                if let animation = animation {
                    withAnimation(animation) {
                        cachedImage = image
                    }
                } else {
                    cachedImage = image
                }
            }
        } catch {
            print("CachedAsyncImage: Failed to load image from \(url): \(error)")
        }
    }
}

// Convenience initializer with default content transformation
extension CachedAsyncImage where Content == Image {
    init(
        url: URL?,
        scale: CGFloat = 1.0,
        animation: Animation? = .default,
        @ViewBuilder placeholder: @escaping () -> Placeholder
    ) {
        self.init(
            url: url,
            scale: scale,
            animation: animation,
            content: { $0 },
            placeholder: placeholder
        )
    }
} 