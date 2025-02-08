import SwiftUI

#if os(iOS)
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
                            VideoPlayerView(video: video, 
                                          showBackButton: false, 
                                          isVisible: .constant(index == currentIndex)) { _ in
                                prefetchVideos(currentIndex: index)
                            }
                            .environmentObject(viewModel)
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
    
    private func prefetchVideos(currentIndex: Int) {
        // Prefetch next 2 videos
        let nextIndices = (1...2).compactMap { offset -> Int? in
            let index = currentIndex + offset
            return index < viewModel.videos.count ? index : nil
        }
        
        let videosToPreload = nextIndices.map { viewModel.videos[$0] }
        
        // Cancel any prefetch tasks for videos we've moved past
        let previousIndices = (-2...0).compactMap { offset -> Int? in
            let index = currentIndex + offset
            return index >= 0 ? index : nil
        }
        
        // Cancel prefetch for videos we've moved past
        previousIndices.forEach { index in
            if let videoURL = URL(string: viewModel.videos[index].videoURL) {
                Task {
                    await VideoAssetLoader.shared.cancelPrefetch(for: videoURL)
                }
            }
        }
        
        // Start prefetching upcoming videos
        videosToPreload.forEach { video in
            if let url = URL(string: video.videoURL) {
                Task {
                    await VideoAssetLoader.shared.prefetchAsset(for: url)
                }
            }
        }
    }
}

extension UIView {
    var subviews: [UIView] {
        Mirror(reflecting: self).children.compactMap { $0.value as? UIView }
    }
}
#endif