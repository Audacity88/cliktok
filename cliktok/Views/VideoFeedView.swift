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
                                .tag(index)
                        }
                    }
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
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
        .onAppear {
            // Configure for vertical scrolling
            configureVerticalScrolling()
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
    
    private func configureVerticalScrolling() {
        // Configure TabView for vertical scrolling
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first {
            
            // Hide tab bar
            UITabBar.appearance().isHidden = true
            
            // Find and configure collection views
            let collectionViews = findCollectionView(in: window)
            for collectionView in collectionViews {
                // Force vertical scrolling
                if let layout = collectionView.collectionViewLayout as? UICollectionViewFlowLayout {
                    layout.scrollDirection = .vertical
                }
                
                // Configure scrolling behavior
                collectionView.isPagingEnabled = true
                collectionView.showsVerticalScrollIndicator = false
                collectionView.showsHorizontalScrollIndicator = false
                collectionView.alwaysBounceVertical = true
                collectionView.alwaysBounceHorizontal = false
                collectionView.bounces = false
                
                // Adjust content insets
                collectionView.contentInsetAdjustmentBehavior = .never
                collectionView.verticalScrollIndicatorInsets = .zero
                
                // Set scroll view delegate to handle paging
                if let scrollView = collectionView as? UIScrollView {
                    scrollView.delegate = nil // Remove any existing delegate
                    scrollView.decelerationRate = .fast
                }
            }
        }
    }
    
    private func findCollectionView(in view: UIView) -> [UICollectionView] {
        var collectionViews = [UICollectionView]()
        
        if let collectionView = view as? UICollectionView {
            collectionViews.append(collectionView)
        }
        
        for subview in view.subviews {
            collectionViews.append(contentsOf: findCollectionView(in: subview))
        }
        
        return collectionViews
    }
}

extension UIView {
    var subviews: [UIView] {
        Mirror(reflecting: self).children.compactMap { $0.value as? UIView }
    }
}
#endif 