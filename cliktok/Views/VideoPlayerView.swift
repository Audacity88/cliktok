import SwiftUI
import AVKit
import AVFoundation
import FirebaseFirestore
import FirebaseAuth

#if os(iOS)

// Video Asset Loader to handle caching and streaming
actor VideoAssetLoader {
    static let shared = VideoAssetLoader()
    
    enum PrefetchPriority {
        case high
        case medium
        case low
    }
    
    private let cache: URLCache
    private var assetCache = NSCache<NSURL, AVAsset>()
    private var loadingAssets: [URL: Task<AVAsset, Error>] = [:]
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]
    private var preloadedData: [URL: Data] = [:]
    
    private init() {
        print("VideoAssetLoader: Initializing with 512MB cache")
        let cacheSizeInBytes = 512 * 1024 * 1024
        self.cache = URLCache(memoryCapacity: cacheSizeInBytes / 4,
                            diskCapacity: cacheSizeInBytes,
                            diskPath: "video_cache")
        
        // Configure asset cache
        assetCache.countLimit = 10
        assetCache.totalCostLimit = 256 * 1024 * 1024
    }
    
    func loadAsset(for url: URL) async throws -> AVAsset {
        let startTime = Date()
        print("VideoAssetLoader: Starting to load asset for URL: \(url)")
        
        // Return cached asset if available
        if let cachedAsset = assetCache.object(forKey: url as NSURL) {
            print("VideoAssetLoader: Found cached asset, returning immediately")
            return cachedAsset
        }
        
        // Check if there's already a loading task
        if let existingTask = loadingAssets[url] {
            print("VideoAssetLoader: Using existing loading task for URL")
            return try await existingTask.value
        }
        
        print("VideoAssetLoader: Creating new loading task")
        let task = Task<AVAsset, Error> {
            // If we have preloaded data, create an asset from it
            if let preloadedData = preloadedData[url] {
                print("VideoAssetLoader: Using preloaded data")
                let asset = try await createAssetFromData(preloadedData, for: url)
                assetCache.setObject(asset, forKey: url as NSURL)
                return asset
            }
            
            // Create asset with streaming optimizations
            let assetOptions: [String: Any] = [
                AVURLAssetAllowsExpensiveNetworkAccessKey: true,
                AVURLAssetPreferPreciseDurationAndTimingKey: false
            ]
            
            print("VideoAssetLoader: Creating streaming asset")
            let asset = AVURLAsset(url: url, options: assetOptions)
            
            // Load enough data to establish playback
            print("VideoAssetLoader: Loading initial metadata")
            try await loadInitialMetadata(for: asset)
            
            assetCache.setObject(asset, forKey: url as NSURL)
            print("VideoAssetLoader: Asset prepared in \(Date().timeIntervalSince(startTime))s")
            return asset
        }
        
        loadingAssets[url] = task
        
        do {
            let asset = try await task.value
            loadingAssets[url] = nil
            return asset
        } catch {
            loadingAssets[url] = nil
            print("VideoAssetLoader: Error loading asset: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func loadInitialMetadata(for asset: AVURLAsset) async throws {
        print("VideoAssetLoader: Loading essential metadata")
        // Load essential properties to ensure valid playback
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                // Load tracks first
                let tracks = try await asset.load(.tracks)
                guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                    throw NSError(domain: "VideoLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No video track found"])
                }
                
                // Load essential video track properties
                let descriptions = try await videoTrack.load(.formatDescriptions)
                guard !descriptions.isEmpty else {
                    throw NSError(domain: "VideoLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "No format descriptions found"])
                }
            }
            
            // Wait for metadata loading to complete
            try await group.waitForAll()
        }
        print("VideoAssetLoader: Metadata loaded successfully")
    }
    
    private func createAssetFromData(_ data: Data, for url: URL) async throws -> AVAsset {
        let fileManager = FileManager.default
        let cacheDir = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let fileURL = cacheDir.appendingPathComponent(url.lastPathComponent)
        
        // Write data to temporary file
        try data.write(to: fileURL)
        
        // Create asset from file
        let asset = AVURLAsset(url: fileURL)
        
        // Load essential metadata
        try await loadInitialMetadata(for: asset)
        
        // Schedule cleanup
        Task {
            try? await Task.sleep(nanoseconds: 30 * NSEC_PER_SEC)
            try? fileManager.removeItem(at: fileURL)
        }
        
        return asset
    }
    
    func prefetchWithPriority(for url: URL, priority: PrefetchPriority) async {
        print("VideoAssetLoader: Starting priority prefetch for URL: \(url)")
        
        // Skip if already cached or loading
        guard loadingAssets[url] == nil,
              prefetchTasks[url] == nil,
              assetCache.object(forKey: url as NSURL) == nil else {
            return
        }
        
        // For high priority, load more initial data
        let rangeSize = priority == .high ? 2 * 1024 * 1024 : 1024 * 1024 // 2MB for high priority
        
        let task = Task {
            do {
                let session = URLSession.shared
                var request = URLRequest(url: url)
                request.setValue("bytes=0-\(rangeSize)", forHTTPHeaderField: "Range")
                
                print("VideoAssetLoader: Downloading initial \(rangeSize/1024)KB")
                let (data, response) = try await session.data(for: request)
                
                // If we got a 206 Partial Content response, store the data
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 206 {
                    preloadedData[url] = data
                    print("VideoAssetLoader: Successfully prefetched \(data.count) bytes")
                } else {
                    print("VideoAssetLoader: Server doesn't support range requests, falling back")
                    // Create and cache the full asset
                    _ = try await loadAsset(for: url)
                }
            } catch {
                print("VideoAssetLoader: Prefetch failed for \(url): \(error.localizedDescription)")
            }
        }
        
        prefetchTasks[url] = task
    }
    
    func cleanupAsset(for url: URL) {
        print("VideoAssetLoader: Cleaning up asset for URL: \(url)")
        assetCache.removeObject(forKey: url as NSURL)
        preloadedData.removeValue(forKey: url)
        loadingAssets[url]?.cancel()
        loadingAssets[url] = nil
        prefetchTasks[url]?.cancel()
        prefetchTasks[url] = nil
    }
    
    func clearCache() {
        print("VideoAssetLoader: Clearing all caches")
        assetCache.removeAllObjects()
        preloadedData.removeAll()
        cache.removeAllCachedResponses()
    }
}

struct VideoPlayerView: View {
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @StateObject private var tipViewModel = TipViewModel.shared
    @Environment(\.dismiss) private var dismiss
    let video: Video
    let showBackButton: Bool
    @Binding var clearSearchOnDismiss: Bool
    @Binding var isVisible: Bool
    
    // Player states
    @State private var player: AVPlayer?
    @State private var isPlaying = false
    @State private var isMuted = false
    @State private var isLoadingVideo = false
    @State private var currentTime: Double = 0
    @State private var duration: Double = 0
    @State private var isDraggingProgress = false
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var showPlayButton = false
    @State private var timeObserver: Any?
    
    // Creator and UI states
    @State private var showAddFundsAlert = false
    @State private var showError = false
    @State private var errorMessage = ""
    @State private var showWallet = false
    @State private var totalTips = 0
    @State private var showTipBubble = false
    @State private var showTippedText = false
    @State private var showTipSheet = false
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var creator: User?
    @State private var loopObserver: NSObjectProtocol?
    @State private var errorObserver: NSObjectProtocol?
    let onPrefetch: (([Video]) -> Void)?
    
    init(video: Video, showBackButton: Bool = false, clearSearchOnDismiss: Binding<Bool> = .constant(false), isVisible: Binding<Bool>, onPrefetch: (([Video]) -> Void)? = nil) {
        self.video = video
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
        self._isVisible = isVisible
        self.onPrefetch = onPrefetch
        
        // Configure audio session once at init
        Task {
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
            } catch {
                print("Failed to set audio session category: \(error)")
            }
        }
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
                                    withAnimation {
                                        showControls.toggle()
                                        resetControlsTimer()
                                    }
                                }
                                .allowsHitTesting(duration <= 30) // Only allow tap gesture if no progress bar
                        )
                        .overlay(
                            Group {
                                if duration > 30 && showControls {
                                    VStack {
                                        Spacer()
                                        // Progress bar
                                        ProgressBar(
                                            value: $currentTime,
                                            total: duration,
                                            isDragging: $isDraggingProgress,
                                            onChanged: { newValue in
                                                currentTime = newValue
                                                // Seek while dragging for immediate feedback
                                                let time = CMTime(seconds: newValue, preferredTimescale: 1000)
                                                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                                                resetControlsTimer()
                                            },
                                            onEnded: { newValue in
                                                currentTime = newValue
                                                // Seek with exact timing when drag ends
                                                let time = CMTime(seconds: newValue, preferredTimescale: 1000)
                                                player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                                                    if finished && isPlaying {
                                                        player.play()
                                                    }
                                                }
                                                resetControlsTimer()
                                            }
                                        )
                                        .frame(height: 20)
                                        .padding(.horizontal)
                                        .padding(.bottom, 200) // Fixed position above heart icon
                                        .zIndex(1) // Ensure progress bar is above the tap overlay
                                    }
                                }
                            }
                        )
                        .overlay(
                            Group {
                                if showControls {
                                    Button(action: togglePlayPause) {
                                        Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                            .resizable()
                                            .aspectRatio(contentMode: .fit)
                                            .frame(width: 60, height: 60)
                                            .foregroundColor(.white)
                                            .opacity(0.8)
                                    }
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
                
                // Back Button and Menu
                VStack {
                    if showBackButton {
                        HStack {
                            Button(action: {
                                cleanupPlayer()
                                clearSearchOnDismiss = true
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
                            
                            // Add three-dot menu if user owns the video
                            if video.userID == Auth.auth().currentUser?.uid {
                                Menu {
                                    Button {
                                        showEditSheet = true
                                    } label: {
                                        Label("Edit Video", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete Video", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .frame(width: 44, height: 44) // Increase touch target
                                        .contentShape(Rectangle()) // Make entire frame tappable
                                }
                                .padding(.trailing)
                            }
                        }
                        .padding(.top, 50)
                    } else {
                        // Show menu even when back button is hidden
                        if video.userID == Auth.auth().currentUser?.uid {
                            HStack {
                                Spacer()
                                Menu {
                                    Button {
                                        showEditSheet = true
                                    } label: {
                                        Label("Edit Video", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive) {
                                        showDeleteAlert = true
                                    } label: {
                                        Label("Delete Video", systemImage: "trash")
                                    }
                                } label: {
                                    Image(systemName: "ellipsis")
                                        .font(.title2)
                                        .foregroundColor(.white)
                                        .shadow(radius: 2)
                                        .frame(width: 44, height: 44) // Increase touch target
                                        .contentShape(Rectangle()) // Make entire frame tappable
                                }
                                .padding(.trailing)
                            }
                            .padding(.top, 50)
                        }
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
                                
                                if let creator = creator {
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
                            VStack(spacing: 20) {
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
                    // Load video without autoplaying
                    await loadAndPlayVideo()
                    
                    // Load creator profile and tip data
                    if creator == nil {
                        await feedViewModel.fetchCreators(for: [video])
                        creator = feedViewModel.getCreator(for: video)
                    }
                    await tipViewModel.loadBalance()
                    await tipViewModel.loadTipHistory()
                }
            }
            .onChange(of: isVisible) { newValue in
                if newValue {
                    // Update view count and play when becoming visible
                    Task {
                        print("Video becoming visible: \(video.id)")
                        await feedViewModel.updateVideoStats(video: video)
                        player?.play()
                    }
                } else {
                    print("Video becoming hidden: \(video.id)")
                    player?.pause()
                }
            }
            .onDisappear {
                cleanupPlayer()
            }
            .onChange(of: showEditSheet) { oldValue, newValue in
                if newValue {
                    // Just pause the video when edit sheet is shown
                    player?.pause()
                    isPlaying = false
                } else {
                    // Resume playing from current position when edit sheet is dismissed
                    player?.play()
                    isPlaying = true
                    
                    // Refresh the video data
                    Task {
                        await feedViewModel.loadInitialVideos()
                    }
                }
            }
            .sheet(isPresented: $showEditSheet) {
                VideoEditView(video: video, isPresented: $showEditSheet)
                    .environmentObject(feedViewModel)
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
            .alert("Delete Video", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await feedViewModel.deleteVideo(video)
                            cleanupPlayer()
                            dismiss()
                        } catch {
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this video? This action cannot be undone.")
            }
            .sheet(isPresented: $showWallet) {
                WalletView()
            }
        }
    }
    
    private func loadAndPlayVideo() async {
        guard let url = URL(string: video.videoURL) else {
            print("VideoPlayerView: Invalid URL for video: \(video.id)")
            return
        }
        
        print("VideoPlayerView: Starting to load video from URL: \(url)")
        let startTime = Date()
        
        await MainActor.run {
            isLoadingVideo = true
            duration = 0 // Reset duration
        }
        
        do {
            print("VideoPlayerView: Requesting asset from loader")
            let asset = try await VideoAssetLoader.shared.loadAsset(for: url)
            
            // Load duration asynchronously before creating player item
            let durationValue = try await asset.load(.duration)
            let durationSeconds = CMTimeGetSeconds(durationValue)
            
            print("VideoPlayerView: Creating player item")
            let playerItem = AVPlayerItem(asset: asset)
            playerItem.preferredForwardBufferDuration = 2
            playerItem.automaticallyPreservesTimeOffsetFromLive = false
            
            await MainActor.run {
                print("VideoPlayerView: Setting up player on main thread")
                cleanupPlayer()
                
                // Set duration first
                if durationSeconds.isFinite {
                    self.duration = durationSeconds
                }
                
                let newPlayer = AVPlayer(playerItem: playerItem)
                newPlayer.automaticallyWaitsToMinimizeStalling = false
                newPlayer.isMuted = isMuted
                newPlayer.volume = 1.0
                
                setupTimeObserver(for: newPlayer)
                setupPlayerItemObservers(for: playerItem)
                
                self.player = newPlayer
                
                print("VideoPlayerView: Starting playback")
                newPlayer.play()
                isPlaying = true
                showPlayButton = false
                
                print("VideoPlayerView: Video setup completed in \(Date().timeIntervalSince(startTime))s")
                isLoadingVideo = false
            }
        } catch {
            print("VideoPlayerView: Error loading video: \(error.localizedDescription)")
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.showError = true
                isLoadingVideo = false
            }
        }
    }
    
    private func cleanupPlayer() {
        print("Cleaning up player")
        
        // Remove observers if they exist
        if let loopObserver = loopObserver {
            NotificationCenter.default.removeObserver(loopObserver)
            self.loopObserver = nil
        }
        
        if let errorObserver = errorObserver {
            NotificationCenter.default.removeObserver(errorObserver)
            self.errorObserver = nil
        }
        
        if let player = player, let timeObserver = timeObserver {
            player.removeTimeObserver(timeObserver)
        }
        timeObserver = nil
        
        // Ensure player is muted before cleanup
        player?.isMuted = true
        
        // Pause and nil the player
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
        isPlaying = false
        isLoadingVideo = false  // Reset loading state
        showPlayButton = false  // Reset play button state
    }
    
    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        // Ensure volume is at maximum when unmuting
        if !isMuted {
            player?.volume = 1.0
        }
    }
    
    private func togglePlayPause() {
        print("Toggle play/pause called. Current state - isPlaying: \(isPlaying)")
        if isPlaying {
            player?.pause()
        } else {
            player?.play()
        }
        isPlaying.toggle()
        showPlayButton = !isPlaying
        
        if isPlaying {
            resetControlsTimer()
        } else {
            showControls = true
            controlsTimer?.invalidate()
        }
    }
    
    private func setupTimeObserver(for player: AVPlayer) {
        // Remove existing observer if any
        if let existing = timeObserver {
            player.removeTimeObserver(existing)
            timeObserver = nil
        }
        
        // Get video duration if not already set
        if duration == 0, let currentItem = player.currentItem {
            let durationSeconds = currentItem.asset.duration.seconds
            if durationSeconds.isFinite {
                self.duration = durationSeconds
            }
        }
        
        // Create new time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak player] time in
            guard let player = player else { return }
            
            // Update current time if not dragging
            if !isDraggingProgress {
                let seconds = CMTimeGetSeconds(time)
                if seconds.isFinite {
                    currentTime = seconds
                }
            }
            
            // Update playing state
            let isCurrentlyPlaying = player.rate != 0
            if isPlaying != isCurrentlyPlaying {
                isPlaying = isCurrentlyPlaying
                showPlayButton = !isCurrentlyPlaying
            }
            
            // Hide controls after delay if video is playing
            if isPlaying && showControls && !isDraggingProgress {
                resetControlsTimer()
            }
        }
    }
    
    private func resetControlsTimer() {
        // Cancel existing timer
        controlsTimer?.invalidate()
        
        // Show controls
        withAnimation {
            showControls = true
        }
        
        // Set new timer to hide controls after 3 seconds
        controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
            if isPlaying && !isDraggingProgress {
                withAnimation {
                    showControls = false
                }
            }
        }
    }
    
    private func setupPlayerItemObservers(for playerItem: AVPlayerItem) {
        // Configure looping with a single observer
        let loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: playerItem,
            queue: .main
        ) { [weak player] _ in
            player?.seek(to: .zero)
            player?.play()
        }
        
        // Store the observer for cleanup
        self.loopObserver = loopObserver
        
        // Set up error observation with a single observer
        let errorObserver = NotificationCenter.default.addObserver(
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
        
        // Store the error observer for cleanup
        self.errorObserver = errorObserver
    }
}

// Progress Bar View
struct ProgressBar: View {
    @Binding var value: Double
    let total: Double
    @Binding var isDragging: Bool
    let onChanged: (Double) -> Void
    let onEnded: (Double) -> Void
    
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 20)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { gesture in
                                let ratio = gesture.location.x / geometry.size.width
                                let newValue = total * ratio
                                isDragging = true
                                onChanged(newValue)
                            }
                            .onEnded { gesture in
                                let ratio = gesture.location.x / geometry.size.width
                                let newValue = total * ratio
                                onEnded(newValue)
                                isDragging = false
                            }
                    )
                    .overlay {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Progress track
                                Rectangle()
                                    .fill(Color.white)
                                    .frame(width: geo.size.width * CGFloat(value / total), height: 20)
                                
                                // Handle
                                Circle()
                                    .fill(Color.white)
                                    .frame(width: 20, height: 20)
                                    .position(x: geo.size.width * CGFloat(value / total), y: geo.size.height / 2)
                            }
                        }
                    }
            }
        }
        .frame(height: 20)
    }
}

#endif
