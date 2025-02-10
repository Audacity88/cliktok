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

// Video Controls Overlay
struct VideoControlsOverlay: View {
    let showControls: Bool
    let isPlaying: Bool
    let togglePlayPause: () -> Void
    
    var body: some View {
        Button(action: {
            print("Play/Pause button tapped - isPlaying before tap: \(isPlaying)")
            togglePlayPause()
        }) {
            Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 70, height: 70)  // Slightly larger touch target
                .foregroundColor(.white)
                .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .opacity(showControls ? 0.9 : 0)
        .animation(.easeInOut(duration: 0.2), value: showControls)
    }
}

// Video Progress Overlay
struct VideoProgressOverlay: View {
    let duration: Double
    let showControls: Bool
    @Binding var currentTime: Double
    @Binding var isDraggingProgress: Bool
    let isPlaying: Bool
    let player: AVPlayer
    let resetControlsTimer: () -> Void
    
    var body: some View {
        VStack {
            Spacer()
            ProgressBar(
                value: $currentTime,
                total: duration,
                isDragging: $isDraggingProgress,
                onChanged: { newValue in
                    currentTime = newValue
                    let time = CMTime(seconds: newValue, preferredTimescale: 1000)
                    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
                    resetControlsTimer()
                },
                onEnded: { newValue in
                    currentTime = newValue
                    let time = CMTime(seconds: newValue, preferredTimescale: 1000)
                    player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero) { finished in
                        if finished && isPlaying {
                            player.play()
                        }
                    }
                    resetControlsTimer()
                }
            )
            .padding(.horizontal)
            .padding(.bottom, 200)
            .opacity(showControls || isDraggingProgress ? 1 : 0)
            .animation(.easeInOut(duration: 0.2), value: showControls)
        }
        .contentShape(Rectangle())
    }
}

// Video Menu Button
struct VideoMenuButton: View {
    let showEditSheet: Binding<Bool>
    let showDeleteAlert: Binding<Bool>
    
    var body: some View {
        Menu {
            Button {
                showEditSheet.wrappedValue = true
            } label: {
                Label("Edit Video", systemImage: "pencil")
            }
            
            Button(role: .destructive) {
                showDeleteAlert.wrappedValue = true
            } label: {
                Label("Delete Video", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.title2)
                .foregroundColor(.white)
                .shadow(radius: 2)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .padding(.trailing)
    }
}

// Video Control Buttons
struct VideoControlButtons: View {
    let totalTips: Int
    let tipViewModel: TipViewModel
    let isMuted: Bool
    let video: Video
    @Binding var showTipBubble: Bool
    @Binding var showTippedText: Bool
    @Binding var showAddFundsAlert: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    let toggleMute: () -> Void
    @State private var isHeartFilled = false
    
    var body: some View {
        VStack(spacing: 20) {
            // Like/Tip Button
            VStack(spacing: 20) {
                ZStack(alignment: .center) {
                    // Container for fixed positioning
                    VStack {
                        Spacer()
                            .frame(height: 32)
                    }
                    .frame(width: 100, height: 80)
                    
                    // Heart button with retro styling
                    VStack(spacing: 4) {
                        Button(action: {
                            Task {
                                do {
                                    withAnimation(.spring(response: 0.3, dampingFraction: 0.6)) {
                                        isHeartFilled = true
                                    }
                                    guard let videoId = video.id else { return }
                                    try await tipViewModel.sendMinimumTip(receiverID: video.userID, videoID: videoId)
                                    withAnimation {
                                        showTipBubble = true
                                        showTippedText = true
                                    }
                                    
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
                                Image(systemName: "heart\(isHeartFilled || totalTips > 0 ? ".fill" : "")")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .foregroundColor(isHeartFilled || totalTips > 0 ? .red : .gray)
                                    .shadow(radius: 2)
                                
                                Text("\(totalTips)¢")
                                    .font(.system(size: 12, weight: .bold, design: .monospaced))
                                    .foregroundColor(.gray)
                                    .shadow(radius: 1)
                            }
                        }
                    }
                    .offset(x: 40, y: 35)
                    
                    if showTippedText {
                        Text("Tipped!")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.green)
                            .shadow(radius: 1)
                            .frame(width: 100)
                            .offset(x: 40, y: 27)
                            .transition(.opacity)
                    }
                    
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
                    .foregroundColor(.gray)
                    .shadow(radius: 2)
            }
            .offset(x: 40, y: 10)
            
            // View Count
            VStack(spacing: 4) {
                Image(systemName: "eye.fill")
                    .font(.system(size: 30))
                    .foregroundColor(.gray)
                    .shadow(radius: 2)
                Text("\(video.views)")
                    .foregroundColor(.gray)
                    .font(.system(size: 14, design: .monospaced))
                    .shadow(radius: 2)
            }
            .offset(x: 40, y: 10)
        }
        .padding(.trailing)
    }
}

// Video Info Section
struct VideoInfoSection: View {
    let video: Video
    let creator: User?
    let geometry: GeometryProxy
    let totalTips: Int
    let tipViewModel: TipViewModel
    let isMuted: Bool
    @Binding var showTipBubble: Bool
    @Binding var showTippedText: Bool
    @Binding var showAddFundsAlert: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    let toggleMute: () -> Void
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            RetroVideoInfo(
                title: video.caption.cleaningHTMLTags(),
                description: (video.description ?? "").cleaningHTMLTags(),
                hashtags: video.hashtags,
                creator: creator,
                showCreator: true
            )
            .frame(maxWidth: geometry.size.width * 0.85, alignment: .leading)
            
            Spacer(minLength: 0)
            
            VideoControlButtons(
                totalTips: totalTips,
                tipViewModel: tipViewModel,
                isMuted: isMuted,
                video: video,
                showTipBubble: $showTipBubble,
                showTippedText: $showTippedText,
                showAddFundsAlert: $showAddFundsAlert,
                showError: $showError,
                errorMessage: $errorMessage,
                toggleMute: toggleMute
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 30)
    }
}

// Add this before the VideoPlayerView struct
class VideoPlayerViewModel: NSObject, ObservableObject {
    @Published var player: AVPlayer?
    @Published var isPlaying = false
    @Published var isMuted = false
    @Published var isLoadingVideo = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    @Published var showPlayButton = false
    @Published var errorMessage = ""
    @Published var showError = false
    
    private var timeObserverToken: Any?
    private var observedPlayer: AVPlayer?
    private var videoURL: String?
    private var isVisible: Bool = false
    
    func setVideo(url: String, isVisible: Bool) {
        self.videoURL = url
        self.isVisible = isVisible
    }
    
    func loadAndPlayVideo() async {
        guard let urlString = videoURL,
              let url = URL(string: urlString) else {
            print("VideoPlayerView: Invalid URL for video")
            return
        }
        
        print("VideoPlayerView: Starting to load video from URL: \(url)")
        let startTime = Date()
        
        await MainActor.run {
            isLoadingVideo = true
            duration = 0 // Reset duration
            
            // Stop any existing playback before loading new video
            cleanupPlayer()
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
            
            // Add error handling for playback issues
            playerItem.addObserver(self, forKeyPath: #keyPath(AVPlayerItem.status), options: [.new, .old], context: nil)
            
            await MainActor.run {
                print("VideoPlayerView: Setting up player on main thread")
                
                // Set duration first
                if durationSeconds.isFinite {
                    self.duration = durationSeconds
                }
                
                let newPlayer = AVPlayer(playerItem: playerItem)
                newPlayer.automaticallyWaitsToMinimizeStalling = false
                newPlayer.isMuted = isMuted
                newPlayer.volume = 1.0
                
                setupTimeObserver(for: newPlayer)
                
                self.player = newPlayer
                
                // Only start playing if this video is visible
                if isVisible {
                    print("VideoPlayerView: Starting playback (video is visible)")
                    newPlayer.play()
                    isPlaying = true
                    showPlayButton = false
                } else {
                    print("VideoPlayerView: Video loaded but not playing (video is not visible)")
                    isPlaying = false
                    showPlayButton = true
                }
                
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
    
    override public func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(AVPlayerItem.status) {
            let status: AVPlayerItem.Status
            if let statusNumber = change?[.newKey] as? NSNumber {
                status = AVPlayerItem.Status(rawValue: statusNumber.intValue)!
            } else {
                status = .unknown
            }
            
            switch status {
            case .failed:
                if let playerItem = object as? AVPlayerItem,
                   let error = playerItem.error as NSError? {
                    print("VideoPlayerView: Playback failed with error: \(error.localizedDescription)")
                    
                    // Handle invalid sample cursor error
                    if error.domain == AVFoundationErrorDomain && 
                       (error.localizedDescription.contains("Invalid sample cursor") ||
                        error.localizedDescription.contains("sample reading")) {
                        
                        Task { @MainActor in
                            // Clean up the current player
                            cleanupPlayer()
                            
                            // Clear asset cache for this URL
                            if let urlString = videoURL,
                               let url = URL(string: urlString) {
                                await VideoAssetLoader.shared.cleanupAsset(for: url)
                            }
                            
                            // Try to reload the video after a short delay
                            try? await Task.sleep(nanoseconds: 1 * NSEC_PER_SEC)
                            await loadAndPlayVideo()
                        }
                    } else {
                        Task { @MainActor in
                            errorMessage = error.localizedDescription
                            showError = true
                        }
                    }
                }
            case .readyToPlay:
                print("VideoPlayerView: Player item is ready to play")
            case .unknown:
                print("VideoPlayerView: Player item status is unknown")
            @unknown default:
                print("VideoPlayerView: Player item has unhandled status")
            }
        }
    }
    
    func cleanupPlayer() {
        print("VideoPlayerView: Cleaning up player")
        if let currentPlayer = player {
            currentPlayer.pause()
            
            // Remove KVO observer from player item
            if let playerItem = currentPlayer.currentItem {
                playerItem.removeObserver(self, forKeyPath: #keyPath(AVPlayerItem.status))
            }
            
            // Only remove the time observer if it was added to this player instance
            if currentPlayer === observedPlayer, let token = timeObserverToken {
                print("VideoPlayerView: Removing time observer")
                currentPlayer.removeTimeObserver(token)
                timeObserverToken = nil
                observedPlayer = nil
            }
            
            currentPlayer.replaceCurrentItem(with: nil)
        }
        
        // Clear player and reset state
        player = nil
        isPlaying = false
        isLoadingVideo = false
        currentTime = 0
        duration = 0
        
        // Clean up asset loader cache for this video
        if let urlString = videoURL,
           let url = URL(string: urlString) {
            Task {
                await VideoAssetLoader.shared.cleanupAsset(for: url)
            }
        }
    }
    
    private func setupTimeObserver(for player: AVPlayer) {
        // Remove existing observer if any
        if let existingPlayer = observedPlayer, let token = timeObserverToken {
            print("VideoPlayerView: Removing existing time observer")
            existingPlayer.removeTimeObserver(token)
            timeObserverToken = nil
            observedPlayer = nil
        }
        
        // Create new time observer
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let token = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            guard let self = self else { return }
            
            // Update current time
            let seconds = CMTimeGetSeconds(time)
            if seconds.isFinite {
                self.currentTime = seconds
            }
            
            // Update playing state
            let isCurrentlyPlaying = player.rate != 0
            if self.isPlaying != isCurrentlyPlaying {
                print("Play state changed - isCurrentlyPlaying: \(isCurrentlyPlaying), previous isPlaying: \(self.isPlaying)")
                self.isPlaying = isCurrentlyPlaying
                self.showPlayButton = !isCurrentlyPlaying
            }
        }
        
        // Store the token and player reference
        timeObserverToken = token
        observedPlayer = player
        print("VideoPlayerView: Added new time observer")
    }
    
    func togglePlayPause() {
        if isPlaying {
            player?.pause()
            print("Video PAUSED")
        } else {
            player?.play()
            print("Video PLAYING")
        }
        isPlaying.toggle()
        showPlayButton = !isPlaying
    }
    
    func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
        if !isMuted {
            player?.volume = 1.0
        }
    }
    
    func updateVisibility(_ isVisible: Bool) {
        self.isVisible = isVisible
        if isVisible {
            player?.play()
            isPlaying = true
            showPlayButton = false
        } else {
            player?.pause()
            isPlaying = false
            showPlayButton = true
        }
    }
    
    func seekTo(time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
}

struct VideoPlayerView: View {
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @StateObject private var tipViewModel = TipViewModel.shared
    @StateObject private var playerViewModel = VideoPlayerViewModel()
    @Environment(\.dismiss) private var dismiss
    let video: Video
    let showBackButton: Bool
    @Binding var clearSearchOnDismiss: Bool
    @Binding var isVisible: Bool
    
    // UI states
    @State private var isDraggingProgress = false
    @State private var showControls = true
    @State private var controlsTimer: Timer?
    @State private var showAddFundsAlert = false
    @State private var showWallet = false
    @State private var totalTips = 0
    @State private var showTipBubble = false
    @State private var showTippedText = false
    @State private var showTipSheet = false
    @State private var showDeleteAlert = false
    @State private var showEditSheet = false
    @State private var creator: User?
    @State private var lastControlReset = Date()
    @State private var isResettingControls = false
    @State private var showError = false
    
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
            ZStack(alignment: .top) {
                // Black background
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Video player and controls
                Group {
                    if let player = playerViewModel.player {
                        VideoPlayer(player: player)
                            .edgesIgnoringSafeArea(.all)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .overlay {
                                ZStack {
                                    // Full-screen tap gesture area
                                    Color.black.opacity(0.01)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            print("DEBUG: ====== Background Tap Event ======")
                                            print("DEBUG: Location: Full screen background")
                                            print("DEBUG: Current States:")
                                            print("DEBUG: - showControls: \(showControls)")
                                            print("DEBUG: - showPlayButton: \(playerViewModel.showPlayButton)")
                                            print("DEBUG: - isPlaying: \(playerViewModel.isPlaying)")
                                            print("DEBUG: - controlsTimer active: \(controlsTimer != nil)")
                                            
                                            withAnimation {
                                                showControls.toggle()
                                                print("DEBUG: Controls toggled to: \(showControls)")
                                                
                                                if showControls {
                                                    print("DEBUG: Starting controls auto-hide timer")
                                                    resetControlsTimer()
                                                } else {
                                                    print("DEBUG: Invalidating controls timer")
                                                    controlsTimer?.invalidate()
                                                }
                                            }
                                            print("DEBUG: ================================")
                                        }
                                        .allowsHitTesting(!playerViewModel.showPlayButton)  // Only allow background taps when play button is hidden

                                    // Controls layer
                                    VStack {
                                        Spacer()
                                        
                                        // Center container for play/pause button
                                        ZStack {
                                            // Play/Pause button
                                            VideoControlsOverlay(
                                                showControls: showControls || playerViewModel.showPlayButton,
                                                isPlaying: playerViewModel.isPlaying,
                                                togglePlayPause: playerViewModel.togglePlayPause
                                            )
                                            .allowsHitTesting(true)
                                            .zIndex(100) // Ensure button is on top of all layers
                                        }
                                        .frame(maxWidth: .infinity, maxHeight: 100)  // Fixed height for better touch target
                                        .contentShape(Rectangle())
                                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                                        
                                        Spacer()
                                        
                                        // Progress bar
                                        VideoProgressOverlay(
                                            duration: playerViewModel.duration,
                                            showControls: showControls,
                                            currentTime: $playerViewModel.currentTime,
                                            isDraggingProgress: $isDraggingProgress,
                                            isPlaying: playerViewModel.isPlaying,
                                            player: player,
                                            resetControlsTimer: resetControlsTimer
                                        )
                                        .allowsHitTesting(true)
                                    }
                                }
                            }
                    } else if playerViewModel.isLoadingVideo {
                        ProgressView()
                            .tint(.white)
                    }
                }
                
                // Content overlay
                VStack(spacing: 0) {
                    if showBackButton {
                        HStack {
                            Button(action: {
                                playerViewModel.cleanupPlayer()
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
                            
                            if video.userID == Auth.auth().currentUser?.uid {
                                VideoMenuButton(showEditSheet: $showEditSheet, showDeleteAlert: $showDeleteAlert)
                            }
                        }
                        .padding(.top, 44) // Add padding to account for status bar
                    } else if video.userID == Auth.auth().currentUser?.uid {
                        HStack {
                            Spacer()
                            VideoMenuButton(showEditSheet: $showEditSheet, showDeleteAlert: $showDeleteAlert)
                        }
                        .padding(.top, 44) // Add padding to account for status bar
                    }
                    
                    Spacer()
                    
                    // Overlay Controls
                    VStack {
                        Spacer()
                        
                        VideoInfoSection(
                            video: video,
                            creator: creator,
                            geometry: geometry,
                            totalTips: totalTips,
                            tipViewModel: tipViewModel,
                            isMuted: playerViewModel.isMuted,
                            showTipBubble: $showTipBubble,
                            showTippedText: $showTippedText,
                            showAddFundsAlert: $showAddFundsAlert,
                            showError: $showError,
                            errorMessage: $playerViewModel.errorMessage,
                            toggleMute: playerViewModel.toggleMute
                        )
                    }
                }
                
                // Fixed status bar at the top
                RetroStatusBar()
                    .frame(height: 44)
            }
            .navigationBarHidden(true)
            .edgesIgnoringSafeArea(.all)
            .onAppear {
                print("VideoPlayerView appeared for video: \(video.id)")
                playerViewModel.setVideo(url: video.videoURL, isVisible: isVisible)
                Task {
                    await playerViewModel.loadAndPlayVideo()
                    
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
                    Task {
                        await feedViewModel.updateVideoStats(video: video)
                    }
                }
                playerViewModel.updateVisibility(newValue)
            }
            .onDisappear {
                playerViewModel.cleanupPlayer()
            }
            .onChange(of: showEditSheet) { oldValue, newValue in
                if newValue {
                    // Just pause the video when edit sheet is shown
                    playerViewModel.player?.pause()
                    playerViewModel.isPlaying = false
                } else {
                    // Resume playing from current position when edit sheet is dismissed
                    playerViewModel.player?.play()
                    playerViewModel.isPlaying = true
                    
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
                Text(playerViewModel.errorMessage)
            }
            .alert("Delete Video", isPresented: $showDeleteAlert) {
                Button("Delete", role: .destructive) {
                    Task {
                        do {
                            try await feedViewModel.deleteVideo(video)
                            playerViewModel.cleanupPlayer()
                            dismiss()
                        } catch {
                            playerViewModel.errorMessage = error.localizedDescription
                            playerViewModel.showError = true
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
    
    private func resetControlsTimer() {
        guard !isResettingControls else { return }
        isResettingControls = true
        
        // Cancel existing timer
        controlsTimer?.invalidate()
        
        // Show controls
        withAnimation {
            showControls = true
            print("Controls SHOWN - resetControlsTimer()")
        }
        
        lastControlReset = Date()
        
        // Only set timer if we're playing
        if playerViewModel.isPlaying && !isDraggingProgress {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                if playerViewModel.isPlaying && !isDraggingProgress {
                    withAnimation {
                        showControls = false
                        print("Controls HIDDEN - timer expired")
                    }
                } else {
                    print("Controls NOT hidden - isPlaying: \(playerViewModel.isPlaying), isDraggingProgress: \(isDraggingProgress)")
                }
                isResettingControls = false
            }
        } else {
            isResettingControls = false
        }
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
            ZStack(alignment: .leading) {
                // Background track
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                
                // Progress track
                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * CGFloat(value / total), height: 4)
                
                // Handle
                Circle()
                    .fill(Color.green)
                    .frame(width: 12, height: 12)
                    .position(x: geometry.size.width * CGFloat(value / total), y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())  // Make entire area tappable
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = max(0, min(gesture.location.x / geometry.size.width, 1))
                        let newValue = total * Double(ratio)
                        isDragging = true
                        onChanged(newValue)
                    }
                    .onEnded { gesture in
                        let ratio = max(0, min(gesture.location.x / geometry.size.width, 1))
                        let newValue = total * Double(ratio)
                        onEnded(newValue)
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }
}

#endif
