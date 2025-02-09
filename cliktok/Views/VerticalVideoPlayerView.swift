import SwiftUI

struct VerticalVideoPlayerView: View {
    let videos: [Video]
    let startingVideo: Video
    var showBackButton: Bool
    @Binding var clearSearchOnDismiss: Bool
    @State private var currentIndex: Int
    @State private var dragOffset = CGSize.zero
    @State private var opacity: Double = 1.0
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    
    init(videos: [Video], startingVideo: Video, showBackButton: Bool, clearSearchOnDismiss: Binding<Bool>) {
        self.videos = videos
        self.startingVideo = startingVideo
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
        
        // Find the index of the starting video
        let startIndex = videos.firstIndex(where: { $0.id == startingVideo.id }) ?? 0
        self._currentIndex = State(initialValue: startIndex)
    }
    
    var body: some View {
        GeometryReader { geometry in
            let width = max(1, geometry.size.width)  // Prevent zero width
            let height = max(1, geometry.size.height) // Prevent zero height
            
            ZStack {
                Color.black
                    .opacity(opacity)
                    .edgesIgnoringSafeArea(.all)
                
                if videos.isEmpty {
                    Text("No videos available")
                        .foregroundColor(.white)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            VideoPlayerView(
                                video: video, 
                                showBackButton: showBackButton, 
                                clearSearchOnDismiss: $clearSearchOnDismiss,
                                isVisible: .constant(index == currentIndex)
                            )
                            .environmentObject(feedViewModel)
                            .frame(width: width, height: height)
                            .rotationEffect(.degrees(-90))
                            .tag(index)
                        }
                    }
                    .frame(width: height, height: width)
                    .rotationEffect(.degrees(90), anchor: .topLeading)
                    .offset(
                        x: width,
                        y: width / 2 - height / 2
                    )
                    .tabViewStyle(.page(indexDisplayMode: .never))
                    .ignoresSafeArea()
                }
            }
            .onChange(of: currentIndex) { oldValue, newValue in
                // Ensure old video is cleaned up
                if oldValue < videos.count {
                    let oldVideo = videos[oldValue]
                    if let url = URL(string: oldVideo.videoURL) {
                        Task {
                            await VideoAssetLoader.shared.cleanupAsset(for: url)
                        }
                    }
                }
                
                // Prefetch next video if available
                if newValue + 1 < videos.count {
                    let nextVideo = videos[newValue + 1]
                    if let url = URL(string: nextVideo.videoURL) {
                        Task {
                            await VideoAssetLoader.shared.prefetchWithPriority(for: url, priority: .medium)
                        }
                    }
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    clearSearchOnDismiss = true
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.white)
                        .imageScale(.large)
                }
            }
        }
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    // Only allow horizontal dragging
                    if abs(gesture.translation.width) > abs(gesture.translation.height) {
                        dragOffset = gesture.translation
                        // Calculate opacity based on drag distance
                        let dragPercentage = min(1, abs(gesture.translation.width) / 200)
                        opacity = 1 - dragPercentage
                    }
                }
                .onEnded { gesture in
                    let threshold: CGFloat = 100
                    if gesture.translation.width > threshold {
                        clearSearchOnDismiss = true
                        withAnimation(.easeOut(duration: 0.3)) {
                            dragOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                            opacity = 0
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            dismiss()
                        }
                    } else {
                        withAnimation(.interactiveSpring()) {
                            dragOffset = .zero
                            opacity = 1
                        }
                    }
                }
        )
        .offset(x: dragOffset.width)
    }
}
