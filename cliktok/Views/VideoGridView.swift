import SwiftUI
import AVKit

struct VideoGridView: View {
    let videos: [Video]
    @State private var selectedVideo: Video?
    
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    var body: some View {
        LazyVGrid(columns: columns, spacing: 1) {
            ForEach(videos) { video in
                VideoThumbnailView(video: video)
                    .aspectRatio(9/16, contentMode: .fill)
                    .frame(height: 180)
                    .clipped()
                    .onTapGesture {
                        selectedVideo = video
                    }
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VideoPlayerView(video: video)
                .edgesIgnoringSafeArea(.all)
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
