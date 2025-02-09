import SwiftUI

#if os(iOS)

// Separate view for video content
struct VideoContentView: View {
    let video: Video
    let index: Int
    let currentIndex: Int
    let onPrefetch: () -> Void
    @EnvironmentObject private var viewModel: VideoFeedViewModel
    
    var body: some View {
        VideoPlayerView(
            video: video,
            showBackButton: false,
            isVisible: .constant(index == currentIndex)
        ) { _ in
            onPrefetch()
        }
        .environmentObject(viewModel)
    }
}

struct VideoFeedView: View {
    @EnvironmentObject private var viewModel: VideoFeedViewModel
    @State private var currentIndex = 0
    @Binding var scrollToTop: Bool
    
    init(scrollToTop: Binding<Bool> = .constant(false)) {
        self._scrollToTop = scrollToTop
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if viewModel.videos.isEmpty {
                    LoadingView()
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                            VideoContentView(
                                video: video,
                                index: index,
                                currentIndex: currentIndex,
                                onPrefetch: { prefetchVideo(at: index) }
                            )
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .rotationEffect(.degrees(-90))
                            .tag(index)
                        }
                    }
                    .frame(
                        width: geometry.size.height,
                        height: geometry.size.width
                    )
                    .rotationEffect(.degrees(90), anchor: .topLeading)
                    .offset(
                        x: geometry.size.width,
                        y: geometry.size.width/2 - geometry.size.height/2
                    )
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
            }
            .onChange(of: currentIndex) { oldValue, newValue in
                if newValue == viewModel.videos.count - 2 {
                    Task {
                        await viewModel.loadMoreVideos()
                    }
                }
                prefetchVideo(at: newValue)
                cancelPrefetch(at: oldValue)
            }
            .onChange(of: scrollToTop) { oldValue, newValue in
                if newValue {
                    withAnimation {
                        currentIndex = 0
                    }
                    scrollToTop = false
                }
            }
            .onChange(of: viewModel.videos.count) { oldValue, newValue in
                if oldValue > newValue {
                    // Video was deleted
                    withAnimation {
                        // If we're at the end, move back one
                        if currentIndex >= newValue {
                            currentIndex = max(0, newValue - 1)
                        }
                    }
                } else if oldValue == 0 && newValue > 0 {
                    // Initial load of videos
                    currentIndex = 0
                }
            }
            .task {
                if viewModel.videos.isEmpty {
                    await viewModel.loadInitialVideos()
                }
            }
        }
    }
    
    private func prefetchVideo(at index: Int) {
        guard index < viewModel.videos.count else { return }
        let video = viewModel.videos[index]
        if let url = URL(string: video.videoURL) {
            Task {
                await VideoAssetLoader.shared.prefetchWithPriority(for: url, priority: .high)
            }
        }
    }
    
    private func cancelPrefetch(at index: Int) {
        guard index < viewModel.videos.count else { return }
        let video = viewModel.videos[index]
        if let url = URL(string: video.videoURL) {
            VideoAssetLoader.shared.cleanupAsset(for: url)
        }
    }
}

extension UIView {
    var subviews: [UIView] {
        Mirror(reflecting: self).children.compactMap { $0.value as? UIView }
    }
}
#endif