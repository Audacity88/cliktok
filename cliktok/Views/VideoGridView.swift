import SwiftUI
import AVKit
import FirebaseAuth

struct VideoGridView: View {
    let videos: [Video]
    let showBackButton: Bool
    @State private var selectedVideo: Video?
    @State private var showEditSheet = false
    @State private var videoToEdit: Video?
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @Binding var clearSearchOnDismiss: Bool
    
    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 1),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 1),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 1)
    ]
    
    init(videos: [Video], showBackButton: Bool, clearSearchOnDismiss: Binding<Bool> = .constant(false)) {
        self.videos = videos
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
    }
    
    var body: some View {
        GeometryReader { geometry in
            let itemWidth = (geometry.size.width - 4) / 3 // 4 = 2 spacing + 2 padding
            
            LazyVGrid(columns: columns, spacing: 1) {
                ForEach(videos) { video in
                    ZStack {
                        VideoThumbnailView(video: video)
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(width: itemWidth, height: itemWidth * (4/3))
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedVideo = video
                            }
                            .contextMenu {
                                if video.userID == Auth.auth().currentUser?.uid {
                                    Button(action: {
                                        videoToEdit = video
                                        showEditSheet = true
                                    }) {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive, action: {
                                        videoToEdit = video
                                        showEditSheet = true
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                }
            }
            .padding(.horizontal, 1)
        }
        .frame(maxWidth: .infinity)
        .fullScreenCover(item: $selectedVideo) { video in
            NavigationView {
                VerticalVideoPlayerView(videos: videos, showBackButton: showBackButton, clearSearchOnDismiss: $clearSearchOnDismiss)
                    .environmentObject(feedViewModel)
                    .edgesIgnoringSafeArea(.all)
            }
        }
        .sheet(isPresented: $showEditSheet) {
            if let video = videoToEdit {
                NavigationView {
                    VideoEditView(video: video, isPresented: $showEditSheet)
                        .environmentObject(feedViewModel)
                }
            }
        }
    }
}

struct VideoThumbnailView: View {
    let video: Video
    
    var body: some View {
        ZStack {
            if let thumbnailURL = video.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(ProgressView())
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .font(.title)
                    )
            }
            
            // Play icon overlay
            Image(systemName: "play.fill")
                .foregroundColor(.white)
                .font(.title2)
                .shadow(radius: 2)
        }
    }
}
