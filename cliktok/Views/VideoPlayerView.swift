import SwiftUI
import AVKit
import AVFoundation
import FirebaseFirestore

#if os(iOS)

// Video Asset Loader to handle caching
actor VideoAssetLoader {
    static let shared = VideoAssetLoader()
    
    private let cache: URLCache
    private var loadingAssets: [URL: Task<AVAsset, Error>] = [:]
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]
    
    private init() {
        // Create a 512MB cache
        let cacheSizeInBytes = 512 * 1024 * 1024
        self.cache = URLCache(memoryCapacity: cacheSizeInBytes / 4,
                            diskCapacity: cacheSizeInBytes,
                            diskPath: "video_cache")
    }
    
    func prefetchAsset(for url: URL) {
        // Don't prefetch if already loading or prefetching
        guard loadingAssets[url] == nil, prefetchTasks[url] == nil else { return }
        
        let task = Task {
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
                
                // If not in cache, download it
                if cache.cachedResponse(for: request) == nil {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
                }
            } catch {
                print("Prefetch failed for \(url): \(error.localizedDescription)")
            }
        }
        
        prefetchTasks[url] = task
    }
    
    func cancelPrefetch(for url: URL) {
        prefetchTasks[url]?.cancel()
        prefetchTasks[url] = nil
    }
    
    func loadAsset(for url: URL) async throws -> AVAsset {
        // Check if we're already loading this asset
        if let existingTask = loadingAssets[url] {
            return try await existingTask.value
        }
        
        // Create a new loading task
        let task = Task {
            let asset: AVAsset
            
            // Create URL request
            let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 60)
            
            // Check cache
            if let cachedResponse = cache.cachedResponse(for: request) {
                let localURL = try await saveToDisk(data: cachedResponse.data)
                asset = AVAsset(url: localURL)
            } else {
                // Download and cache
                let (data, response) = try await URLSession.shared.data(for: request)
                cache.storeCachedResponse(CachedURLResponse(response: response, data: data), for: request)
                let localURL = try await saveToDisk(data: data)
                asset = AVAsset(url: localURL)
            }
            
            // Load essential properties
            try await asset.loadValues(forKeys: ["playable", "duration", "tracks"])
            return asset
        }
        
        loadingAssets[url] = task
        
        // Clean up after loading
        defer {
            Task { await cleanupLoadingTask(for: url) }
        }
        
        return try await task.value
    }
    
    private func cleanupLoadingTask(for url: URL) {
        loadingAssets[url] = nil
    }
    
    private func saveToDisk(data: Data) async throws -> URL {
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = UUID().uuidString + ".mp4"
        let fileURL = tempDir.appendingPathComponent(fileName)
        
        try data.write(to: fileURL)
        return fileURL
    }
}

struct VideoPlayerView: View {
    @StateObject private var tipViewModel = TipViewModel()
    @StateObject private var viewModel = VideoFeedViewModel()
    @Environment(\.dismiss) private var dismiss
    let video: Video
    let showBackButton: Bool
    @State private var player: AVPlayer?
    @State private var isMuted = false
    @State private var showControls = true
    @State private var showAddFundsAlert = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showWallet = false
    @State private var totalTips = 0
    @State private var showTipBubble = false
    @State private var showTippedText = false
    @State private var showTipSheet = false
    @State private var isLoadingVideo = false
    @State private var isPlaying = true
    @State private var showPlayButton = false
    @State private var timeObserverToken: Any?
    let onPrefetch: (([Video]) -> Void)?
    
    init(video: Video, showBackButton: Bool, onPrefetch: (([Video]) -> Void)? = nil) {
        self.video = video
        self.showBackButton = showBackButton
        self.onPrefetch = onPrefetch
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if let player = player {
                    VideoPlayer(player: player)
                        .edgesIgnoringSafeArea(.all)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .overlay(
                            Color.black.opacity(0.01)  // Nearly transparent overlay to catch taps
                                .onTapGesture(count: 1) {
                                    togglePlayPause()
                                }
                        )
                        .overlay(
                            Group {
                                if showPlayButton {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 72))
                                        .foregroundColor(.white.opacity(0.8))
                                        .shadow(radius: 4)
                                        .transition(.opacity)
                                }
                            }
                        )
                } else if isLoadingVideo {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                        .overlay(
                            ProgressView()
                                .tint(.white)
                        )
                } else {
                    Color.black
                        .edgesIgnoringSafeArea(.all)
                }
                
                // Back Button
                VStack {
                    if showBackButton {
                        HStack {
                            Button(action: {
                                cleanupPlayer()
                                dismiss()
                            }) {
                                Image(systemName: "chevron.left")
                                    .font(.title2)
                                    .foregroundColor(.white)
                                    .padding()
                                    .background(Circle().fill(Color.black.opacity(0.5)))
                            }
                            .padding(.leading)
                            Spacer()
                        }
                        .padding(.top, 50)
                    }
                    
                    Spacer()
                    
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
                                    Text(video.hashtags.map { "#\($0)" }.joined(separator: " "))
                                        .foregroundColor(.white.opacity(0.9))
                                        .font(.system(size: 14, weight: .medium))
                                        .shadow(radius: 2)
                                }
                                
                                if let creator = viewModel.getCreator(for: video) {
                                    HStack(alignment: .center, spacing: 10) {
                                        NavigationLink(destination: ProfileView(userId: video.userID)) {
                                            ProfileImageView(imageURL: creator.profileImageURL, size: 40)
                                        }
                                        
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(creator.displayName)
                                                .font(.headline)
                                                .foregroundColor(.white)
                                                .shadow(radius: 2)
                                        }
                                    }
                                    .padding(.top, 8)
                                } else {
                                    ProgressView()
                                        .frame(width: 40, height: 40)
                                        .padding(.top, 8)
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
                        .padding(.horizontal, 20)
                        .padding(.bottom, 30)
                    }
                }
            }
            .navigationBarHidden(true)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                print("VideoPlayerView appeared for video: \(video.id)")
                Task {
                    await loadAndPlayVideo()
                    await viewModel.fetchCreators(for: [video])
                    await tipViewModel.loadBalance()
                    await tipViewModel.loadTipHistory()
                }
            }
            .onDisappear {
                cleanupPlayer()
            }
            .alert("Add Funds", isPresented: $showAddFundsAlert) {
                Button("Add Funds") {
                    showWallet = true
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("You need more funds to tip this video.")
            }
            .alert("Error", isPresented: $showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(errorMessage)
            }
            .sheet(isPresented: $showWallet) {
                WalletView()
            }
        }
    }
    
    private func loadAndPlayVideo() async {
        guard let url = URL(string: video.videoURL) else {
            print("Invalid URL for video: \(video.id)")
            return
        }
        
        print("Loading video from URL: \(url)")
        
        await MainActor.run {
            isLoadingVideo = true
        }
        
        do {
            // Load asset using the caching loader
            let asset = try await VideoAssetLoader.shared.loadAsset(for: url)
            
            // Verify the asset is playable
            guard try await asset.isPlayable else {
                throw NSError(domain: "VideoPlayer", code: -1, userInfo: [NSLocalizedDescriptionKey: "Video is not playable"])
            }
            
            // Create AVPlayerItem with the loaded asset
            let playerItem = AVPlayerItem(asset: asset)
            
            await MainActor.run {
                // Create new player
                let newPlayer = AVPlayer(playerItem: playerItem)
                newPlayer.isMuted = isMuted
                
                // Add periodic time observer for better state management
                let interval = CMTime(seconds: 0.5, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
                timeObserverToken = newPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { _ in
                    isPlaying = newPlayer.timeControlStatus == .playing
                }
                
                // Configure looping
                NotificationCenter.default.removeObserver(self)
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemDidPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { [weak newPlayer] _ in
                    newPlayer?.seek(to: .zero)
                    newPlayer?.play()
                }
                
                // Set up error observation
                NotificationCenter.default.addObserver(
                    forName: .AVPlayerItemFailedToPlayToEndTime,
                    object: playerItem,
                    queue: .main
                ) { notification in
                    if let error = notification.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error {
                        print("Error playing video: \(error.localizedDescription)")
                        errorMessage = error.localizedDescription
                        showError = true
                    }
                }
                
                // Set the player and play
                self.player = newPlayer
                newPlayer.play()
                isPlaying = true
                isLoadingVideo = false
                print("Started playing video: \(video.id)")
            }
        } catch {
            await MainActor.run {
                isLoadingVideo = false
                errorMessage = error.localizedDescription
                showError = true
                print("Error loading video: \(error.localizedDescription)")
            }
        }
    }
    
    private func cleanupPlayer() {
        NotificationCenter.default.removeObserver(self)
        if let player = player, let token = timeObserverToken {
            player.removeTimeObserver(token)
            timeObserverToken = nil
        }
        player?.pause()
        player = nil
        isPlaying = false
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }
    
    private func togglePlayPause() {
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        
        withAnimation {
            isPlaying.toggle()
            showPlayButton = true
        }
        
        // Hide the play button after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
            withAnimation {
                showPlayButton = false
            }
        }
    }
}

#endif