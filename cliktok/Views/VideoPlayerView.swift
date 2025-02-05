import SwiftUI
import AVKit

struct VideoPlayerView: View {
    let video: Video
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                } else {
                    // Show thumbnail or loading placeholder
                    if let thumbnailURL = video.thumbnailURL,
                       let url = URL(string: thumbnailURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Color.black
                    }
                }
                
                // Video controls overlay
                VStack {
                    Spacer()
                    
                    // Video info
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(video.caption)
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold))
                                .shadow(radius: 2)
                            
                            // Hashtags
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack {
                                    ForEach(video.hashtags, id: \.self) { hashtag in
                                        Text("#\(hashtag)")
                                            .foregroundColor(.white)
                                            .font(.system(size: 14))
                                            .shadow(radius: 2)
                                    }
                                }
                            }
                        }
                        Spacer()
                        
                        // Like and view counts
                        VStack(spacing: 12) {
                            VStack(spacing: 4) {
                                Image(systemName: "heart.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 28))
                                Text("\(video.likes)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                            }
                            
                            VStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 28))
                                Text("\(video.views)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                            }
                        }
                        .padding(.trailing)
                    }
                    .padding(.bottom, 30)
                    .padding(.horizontal)
                }
            }
        }
        .onAppear {
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoURL) else { return }
        let playerItem = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: playerItem)
        
        // Enable looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        player?.play()
    }
} 