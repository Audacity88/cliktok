import SwiftUI

struct VerticalVideoPlayerView: View {
    let videos: [Video]
    let showBackButton: Bool
    @State private var currentIndex = 0
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @Binding var clearSearchOnDismiss: Bool
    
    init(videos: [Video], showBackButton: Bool, clearSearchOnDismiss: Binding<Bool> = .constant(false)) {
        self.videos = videos
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)
                
                if videos.isEmpty {
                    Text("No videos available")
                        .foregroundColor(.white)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            VideoPlayerView(video: video, showBackButton: showBackButton, clearSearchOnDismiss: $clearSearchOnDismiss)
                                .environmentObject(feedViewModel)
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
        }
    }
}
