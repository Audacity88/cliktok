import SwiftUI
import AVKit
import AVFoundation

#if os(iOS)
struct VideoPlayerView: View {
    let video: Video
    @StateObject private var viewModel = VideoFeedViewModel()
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var isLiked = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Video Layer
                if let player = player {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .onAppear {
                            player.play()
                            Task {
                                await viewModel.updateVideoStats(video: video, viewed: true)
                            }
                        }
                        .onDisappear {
                            player.pause()
                        }
                } else {
                    // Show thumbnail or loading placeholder
                    if let thumbnailURL = video.thumbnailURL,
                       let url = URL(string: thumbnailURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: geometry.size.width, height: geometry.size.height)
                        } placeholder: {
                            ProgressView()
                        }
                    } else {
                        Color.black
                    }
                }
                
                // Center Play/Pause Button
                Button(action: togglePlayback) {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 72))
                        .shadow(radius: 4)
                }
                .opacity(isPlaying ? 0 : 1) // Hide when playing
                
                // Controls Layer
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
                        
                        // Controls and stats
                        VStack(spacing: 12) {
                            // Mute/Unmute button
                            Button(action: toggleMute) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 28))
                                    .shadow(radius: 2)
                            }
                            
                            // Like button
                            Button(action: toggleLike) {
                                Image(systemName: isLiked ? "heart.fill" : "heart")
                                    .foregroundColor(isLiked ? .red : .white)
                                    .font(.system(size: 28))
                                    .shadow(radius: 2)
                            }
                            Text("\(video.likes)")
                                .foregroundColor(.white)
                                .font(.system(size: 14))
                                .shadow(radius: 2)
                            
                            // View count
                            VStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .foregroundColor(.white)
                                    .font(.system(size: 28))
                                    .shadow(radius: 2)
                                Text("\(video.views)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .shadow(radius: 2)
                            }
                        }
                        .padding(.trailing)
                    }
                    .padding(.bottom, 30)
                    .padding(.horizontal)
                }
            }
            .contentShape(Rectangle()) // Make the entire view tappable
            .onTapGesture {
                togglePlayback()
            }
        }
        .onAppear {
            setupAudioSession()
            setupPlayer()
        }
        .onDisappear {
            player?.pause()
            player = nil
        }
    }
    
    private func setupAudioSession() {
        #if os(iOS)
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
        #endif
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoURL) else { return }
        
        // Create player item with preferred audio settings
        let asset = AVAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Create player and set audio volume
        player = AVPlayer(playerItem: playerItem)
        player?.volume = isMuted ? 0 : 1
        isPlaying = true
        
        // Enable looping
        NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        player?.play()
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.volume = isMuted ? 0 : 1
    }
    
    private func togglePlayback() {
        isPlaying.toggle()
        if isPlaying {
            player?.play()
        } else {
            player?.pause()
        }
    }
    
    private func toggleLike() {
        isLiked.toggle()
        Task {
            await viewModel.updateVideoStats(video: video, liked: isLiked)
        }
    }
}
#endif 