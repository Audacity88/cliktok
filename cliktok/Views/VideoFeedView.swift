import SwiftUI

enum SwipeDirection {
    case left
    case right
}

struct VideoFeedView: View {
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var currentIndex = 0
    @GestureState private var dragOffset: CGFloat = 0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if viewModel.videos.isEmpty {
                    ProgressView()
                        .tint(.white)
                } else {
                    // Current video
                    VideoPlayerView(video: viewModel.videos[currentIndex])
                        .offset(x: dragOffset)
                        .gesture(
                            DragGesture()
                                .updating($dragOffset) { value, state, _ in
                                    state = value.translation.width
                                }
                                .onEnded { value in
                                    let threshold = geometry.size.width * 0.5
                                    if value.translation.width > threshold {
                                        handleSwipe(.right)
                                    } else if value.translation.width < -threshold {
                                        handleSwipe(.left)
                                    }
                                }
                        )
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
        .task {
            await viewModel.loadInitialVideos()
        }
    }
    
    private func handleSwipe(_ direction: SwipeDirection) {
        withAnimation {
            viewModel.handleSwipe(video: viewModel.videos[currentIndex], direction: direction)
            
            switch direction {
            case .left:
                if currentIndex < viewModel.videos.count - 1 {
                    currentIndex += 1
                }
            case .right:
                if currentIndex > 0 {
                    currentIndex -= 1
                }
            }
            
            // Load more videos if we're near the end
            if currentIndex >= viewModel.videos.count - 2 {
                Task {
                    await viewModel.loadMoreVideos()
                }
            }
        }
    }
} 