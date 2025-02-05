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
                            VideoPlayerView(video: video)
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
        .onChange(of: currentIndex) { newIndex in
            // Load more videos if we're near the end
            if newIndex >= viewModel.videos.count - 2 {
                Task {
                    await viewModel.loadMoreVideos()
                }
            }
        }
        .task {
            await viewModel.loadInitialVideos()
        }
    }
}

extension UIView {
    var subviews: [UIView] {
        Mirror(reflecting: self).children.compactMap { $0.value as? UIView }
    }
}
#endif 