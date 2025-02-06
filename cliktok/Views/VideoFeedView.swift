import SwiftUI

#if os(iOS)
struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if viewModel.videos.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(viewModel.videos.enumerated()), id: \.element.id) { index, video in
                            VideoPlayerView(video: video, showBackButton: false) { _ in
                                prefetchVideos(currentIndex: index)
                            }
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
                        y: -geometry.size.height/2 + geometry.size.width/2
                    )
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
                
                // Loading indicator for more videos
                if viewModel.isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                            .tint(.white)
                            .padding(.bottom, 20)
                    }
                }
            }
        }
        .onChange(of: currentIndex) { oldValue, newValue in
            prefetchVideos(currentIndex: newValue)
            
            // Load more videos if we're near the end
            if newValue >= viewModel.videos.count - 2 {
                Task {
                    await viewModel.loadMoreVideos()
                }
            }
        }
        .task {
            await viewModel.loadInitialVideos()
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