import SwiftUI
import AVKit
import AVFoundation

#if os(iOS)
struct VideoPlayerView: View {
    let video: Video
    @StateObject private var viewModel = VideoFeedViewModel()
    @StateObject private var tipViewModel = TipViewModel()
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var isLiked = false
    @State private var showControls = true
    @State private var showTipAlert = false
    @State private var showAddFundsAlert = false
    @State private var tipSent = false
    
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
                            isPlaying = true
                            Task {
                                await viewModel.updateVideoStats(video: video, viewed: true)
                                await tipViewModel.loadBalance()
                            }
                        }
                        .onDisappear {
                            player.pause()
                            isPlaying = false
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
                
                // Overlay Controls
                VStack {
                    Spacer()
                    
                    // Video info and controls
                    HStack(alignment: .bottom, spacing: 16) {
                        // Video details
                        VStack(alignment: .leading, spacing: 4) {
                            Text(video.caption)
                                .foregroundColor(.white)
                                .font(.system(size: 16, weight: .semibold))
                                .shadow(radius: 2)
                                .multilineTextAlignment(.leading)
                            
                            if !video.hashtags.isEmpty {
                                Text(video.hashtags.joined(separator: " "))
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .shadow(radius: 2)
                            }
                        }
                        .frame(maxWidth: geometry.size.width * 0.7, alignment: .leading)
                        
                        Spacer()
                        
                        // Control buttons
                        VStack(spacing: 24) {
                            // Like/Tip Button
                            Button(action: {
                                if !isLiked {
                                    showTipAlert = true
                                }
                            }) {
                                VStack(spacing: 4) {
                                    Image(systemName: isLiked ? "heart.fill" : "heart")
                                        .font(.system(size: 30))
                                        .foregroundColor(isLiked ? .red : .white)
                                        .shadow(radius: 2)
                                    if tipSent {
                                        Text("Tipped!")
                                            .foregroundColor(.white)
                                            .font(.system(size: 12))
                                            .shadow(radius: 2)
                                    }
                                }
                            }
                            .disabled(tipViewModel.isProcessing)
                            
                            // Mute Button
                            Button(action: toggleMute) {
                                Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                            }
                            
                            // View Count
                            VStack(spacing: 4) {
                                Image(systemName: "eye.fill")
                                    .font(.system(size: 30))
                                    .foregroundColor(.white)
                                    .shadow(radius: 2)
                                Text("\(video.views)")
                                    .foregroundColor(.white)
                                    .font(.system(size: 14))
                                    .shadow(radius: 2)
                            }
                        }
                        .padding(.trailing)
                    }
                    .padding(.bottom, 44)
                    .padding(.horizontal)
                }
            }
        }
        .alert("Send Tip", isPresented: $showTipAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Send $0.01") {
                Task {
                    do {
                        guard let videoID = video.id else { return }
                        try await tipViewModel.sendTip(to: video.userID, for: videoID)
                        isLiked = true
                        tipSent = true
                        
                        // Trigger tip animation
                        withAnimation(.spring()) {
                            tipSent = true
                        }
                        // Reset tip sent status after animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                            tipSent = false
                        }
                    } catch {
                        if (error as NSError).code == 402 {
                            showAddFundsAlert = true
                        }
                    }
                }
            }
        } message: {
            Text("Send a $0.01 tip to the creator?")
        }
        .alert("Insufficient Balance", isPresented: $showAddFundsAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Add Funds") {
                Task {
                    do {
                        try await tipViewModel.addFunds(1.00) // Add $1.00
                    } catch {
                        // Handle error
                    }
                }
            }
        } message: {
            Text("Your balance is too low. Would you like to add more funds?")
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
        let asset = AVURLAsset(url: url)
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