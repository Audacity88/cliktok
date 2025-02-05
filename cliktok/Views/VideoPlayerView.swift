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
    @State private var showAddFundsAlert = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var totalTips = 0
    @State private var showTipBubble = false
    @State private var showTippedText = false
    
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
                            VStack(spacing: 20) {
                                ZStack(alignment: .center) {
                                    // Container for fixed positioning
                                    VStack {
                                        Spacer()
                                            .frame(height: 32) // Match heart height
                                    }
                                    .frame(width: 100, height: 80) // Fixed container size
                                    
                                    // Heart button
                                    VStack(spacing: 4) {
                                        Button(action: {
                                            Task {
                                                do {
                                                    guard let videoId = video.id else { return }
                                                    try await tipViewModel.sendMinimumTip(receiverID: video.userID, videoID: videoId)
                                                    totalTips += 1
                                                    
                                                    // Show both animations
                                                    withAnimation {
                                                        showTipBubble = true
                                                        showTippedText = true
                                                    }
                                                    
                                                    // Hide animations after delay
                                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                                        showTipBubble = false
                                                        showTippedText = false
                                                    }
                                                } catch PaymentError.insufficientFunds {
                                                    showAddFundsAlert = true
                                                } catch {
                                                    showError = true
                                                    errorMessage = error.localizedDescription
                                                }
                                            }
                                        }) {
                                            VStack(spacing: 4) {
                                                Image(systemName: "heart\(totalTips > 0 ? ".fill" : "")")
                                                    .resizable()
                                                    .frame(width: 32, height: 32)
                                                    .foregroundColor(totalTips > 0 ? .red : .white)
                                                    .shadow(radius: 2)
                                                
                                                if totalTips > 0 {
                                                    Text("\(totalTips)¢")
                                                        .font(.system(size: 12, weight: .bold))
                                                        .foregroundColor(.white)
                                                        .shadow(radius: 1)
                                                }
                                            }
                                        }
                                    }
                                    .offset(x: 40, y: 35)
                                    
                                    // Tipped text overlay
                                    if showTippedText {
                                        Text("Tipped!")
                                            .font(.system(size: 12))
                                            .foregroundColor(.white)
                                            .shadow(radius: 1)
                                            .frame(width: 100)
                                            .offset(x: 40, y: 27)
                                            .transition(.opacity)
                                    }
                                    
                                    // Tip bubble
                                    if showTipBubble {
                                        TipBubbleView()
                                            .offset(x: 60, y: -30)
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
                            .offset(x: 40, y: 10) 
                            
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
                            .offset(x: 40, y: 10) 
                        }
                        .padding(.trailing)
                    }
                    .padding(.bottom, 44)
                    .padding(.horizontal)
                }
            }
        }
        .alert("Insufficient Balance", isPresented: $showAddFundsAlert) {
            Button("Add Funds") {
                Task {
                    do {
                        try await tipViewModel.addFunds(1.00) // Add $1.00
                        await tipViewModel.loadBalance()
                    } catch {
                        showError = true
                        errorMessage = error.localizedDescription
                    }
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your balance is too low. Would you like to add more funds?")
        }
        .alert("Error", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
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
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Failed to set up audio session: \(error.localizedDescription)")
        }
    }
    
    private func setupPlayer() {
        guard let url = URL(string: video.videoURL) else { return }
        
        // Create player item with preferred audio settings
        let asset = AVURLAsset(url: url)
        let playerItem = AVPlayerItem(asset: asset)
        
        // Create player and set audio volume
        let player = AVPlayer(playerItem: playerItem)
        player.isMuted = isMuted
        self.player = player
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
}
#endif