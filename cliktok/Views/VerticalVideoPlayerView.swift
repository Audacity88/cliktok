import SwiftUI

struct VerticalVideoPlayerView: View {
    let videos: [Video]
    let startingVideo: Video
    var showBackButton: Bool
    @Binding var clearSearchOnDismiss: Bool
    @State private var currentIndex: Int
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
                Color.black.edgesIgnoringSafeArea(.all)
                
                if videos.isEmpty {
                    Text("No videos available")
                        .foregroundColor(.white)
                } else {
                    TabView(selection: $currentIndex) {
                        ForEach(Array(videos.enumerated()), id: \.element.id) { index, video in
                            VideoPlayerView(video: video, showBackButton: showBackButton, clearSearchOnDismiss: $clearSearchOnDismiss)
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
    }
}
