import SwiftUI
import AVKit
import AVFoundation

class VideoPlayerViewModel: NSObject, ObservableObject {
    // Add static property to track currently playing instance
    private static var currentlyPlayingViewModel: VideoPlayerViewModel?
    
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
    private var hideControls: (() -> Void)?
    private var isInCleanupState = false
    private var isValidForPlayback = false
    private var lastPlaybackStartTime: Date?
    private var visibilityDebounceTask: Task<Void, Never>?
    private var isInVisibilityTransition = false
    private var lastVisibilityUpdate = Date.distantPast
    private var isPlaybackStarting = false
    private var cleanupDebounceTask: Task<Void, Never>?
    private var pendingVisibilityUpdate: Bool?
    private var isLoadingTask: Task<Void, Never>?
    
    func setVideo(url: String, isVisible: Bool, hideControls: @escaping () -> Void) {
        print("VideoPlayerView: Setting video URL: \(url), isVisible: \(isVisible)")
        
        // Cancel any existing loading task
        isLoadingTask?.cancel()
        isLoadingTask = nil  // Clear it immediately
        
        self.videoURL = url
        self.isVisible = isVisible
        self.hideControls = hideControls
        self.isInCleanupState = false
        self.isValidForPlayback = false
        self.lastPlaybackStartTime = nil
        self.visibilityDebounceTask?.cancel()
        self.visibilityDebounceTask = nil
        self.isInVisibilityTransition = false
        self.lastVisibilityUpdate = Date()
        self.isPlaybackStarting = false
        self.cleanupDebounceTask?.cancel()
        self.cleanupDebounceTask = nil
        self.pendingVisibilityUpdate = nil
        
        // Start loading immediately if visible
        if isVisible {
            Task {
                await loadAndPlayVideo()
            }
        }
    }
    
    func loadAndPlayVideo() async {
        print("VideoPlayerView: Starting loadAndPlayVideo")
        
        // Prevent multiple concurrent loads
        if isLoadingTask != nil {
            print("VideoPlayerView: Load already in progress, skipping")
            return
        }
        
        // Create loading task
        isLoadingTask = Task {
            // Stop any currently playing video first
            if let currentPlayer = VideoPlayerViewModel.currentlyPlayingViewModel,
               currentPlayer !== self {
                await MainActor.run {
                    print("VideoPlayerView: Stopping previous video")
                    currentPlayer.cleanupPlayer()
                }
            }
            
            guard let urlString = videoURL else {
                print("VideoPlayerView: No video URL provided")
                return
            }
            
            var finalURLString = urlString
            
            // Try to extract identifier from URL if it's an archive.org URL
            if urlString.contains("archive.org/download/") {
                let components = urlString.components(separatedBy: "/download/")
                if components.count > 1 {
                    let idComponents = components[1].components(separatedBy: "/")
                    if let identifier = idComponents.first {
                        do {
                            // Try to get the actual video URL
                            let actualURL = try await InternetArchiveAPI.getActualVideoURL(identifier: identifier)
                            print("VideoPlayerView: Using actual video URL: \(actualURL)")
                            finalURLString = actualURL
                        } catch {
                            print("VideoPlayerView: Failed to get actual video URL for \(identifier): \(error.localizedDescription)")
                            // Continue with the original URL as fallback
                        }
                    }
                }
            }
            
            guard let url = URL(string: finalURLString) else {
                print("VideoPlayerView: Invalid URL for video: \(finalURLString)")
                return
            }
            
            print("VideoPlayerView: Starting to load video from URL: \(url), isVisible: \(isVisible)")
            let startTime = Date()
            
            await MainActor.run {
                isLoadingVideo = true
                duration = 0 // Reset duration
                
                // Only cleanup existing player if we're not just updating the URL
                if player != nil {
                    cleanupPlayer()
                }
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
                    self.isValidForPlayback = true
                    
                    // If this video should be visible, make it the currently playing video
                    if isVisible {
                        print("VideoPlayerView: Video is visible, setting as current")
                        VideoPlayerViewModel.currentlyPlayingViewModel = self
                        // Don't start playing here - wait for ready to play status
                        isPlaying = false
                        showPlayButton = true
                    } else {
                        print("VideoPlayerView: Video is not visible, staying paused")
                        isPlaying = false
                        showPlayButton = true
                    }
                    
                    print("VideoPlayerView: Video setup completed in \(Date().timeIntervalSince(startTime))s")
                    isLoadingVideo = false
                }
            } catch {
                print("VideoPlayerView: Error loading video for URL \(url): \(error.localizedDescription)")
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.showError = true
                    isLoadingVideo = false
                }
            }
        }
        
        // Wait for the loading task to complete
        do {
            try await isLoadingTask?.value
        } catch {
            print("VideoPlayerView: Loading task cancelled or failed")
        }
        
        // Clear loading task at the end
        isLoadingTask = nil
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
                    print("VideoPlayerView: Playback failed for URL \(videoURL ?? "unknown"): \(error.localizedDescription)")
                    
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
                print("VideoPlayerView: Player item is ready to play, isVisible: \(isVisible)")
                Task { @MainActor in
                    // Only handle ready-to-play if we're still in a valid state
                    guard isValidForPlayback else {
                        print("VideoPlayerView: Ignoring ready-to-play event - player is no longer valid")
                        return
                    }
                    
                    // Check for any pending visibility update
                    let shouldBeVisible = pendingVisibilityUpdate ?? isVisible
                    
                    if shouldBeVisible {
                        print("VideoPlayerView: Video is ready and should be visible, starting playback")
                        isPlaybackStarting = true
                        VideoPlayerViewModel.currentlyPlayingViewModel = self
                        player?.play()
                        isPlaying = true
                        showPlayButton = false
                        lastPlaybackStartTime = Date()
                        
                        // Hide controls after a delay when auto-playing
                        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
                            if self?.isPlaying == true {
                                self?.hideControls?()
                            }
                        }
                        
                        // Mark playback as started after a short delay
                        Task {
                            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                            isPlaybackStarting = false
                        }
                    } else {
                        print("VideoPlayerView: Video is ready but should not be visible, staying paused")
                        isPlaying = false
                        showPlayButton = true
                    }
                    
                    // Clear pending update since we've handled it
                    pendingVisibilityUpdate = nil
                }
            case .unknown:
                print("VideoPlayerView: Player item status is unknown")
            @unknown default:
                print("VideoPlayerView: Player item has unhandled status")
            }
        }
    }
    
    func cleanupPlayer() {
        // Cancel any existing cleanup debounce task and loading task
        cleanupDebounceTask?.cancel()
        isLoadingTask?.cancel()
        isLoadingTask = nil
        
        // If we're starting playback or just started, debounce the cleanup
        if isPlaybackStarting || (lastPlaybackStartTime != nil && 
           Date().timeIntervalSince(lastPlaybackStartTime!) < 2.0) {
            print("VideoPlayerView: Debouncing cleanup - playback starting or recently started")
            
            cleanupDebounceTask = Task { @MainActor in
                do {
                    try await Task.sleep(nanoseconds: 2_000_000_000) // Wait 2 seconds
                    if !Task.isCancelled {
                        performCleanup()
                    }
                } catch {
                    print("VideoPlayerView: Cleanup debounce task cancelled")
                }
            }
            return
        }
        
        performCleanup()
    }
    
    private func performCleanup() {
        // Prevent cleanup during visibility transitions or if already cleaning up
        guard !isInVisibilityTransition && !isInCleanupState else {
            print("VideoPlayerView: Skipping cleanup - in transition or cleanup state")
            return
        }
        
        isInCleanupState = true
        isValidForPlayback = false
        print("VideoPlayerView: Cleaning up player")
        
        // Remove this instance from currently playing if it is the current one
        if VideoPlayerViewModel.currentlyPlayingViewModel === self {
            print("VideoPlayerView: Removing self from currently playing")
            VideoPlayerViewModel.currentlyPlayingViewModel = nil
        }
        
        if let currentPlayer = player {
            print("VideoPlayerView: Pausing and cleaning up current player")
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
            
            // Ensure item is removed and player is deallocated
            currentPlayer.replaceCurrentItem(with: nil)
        }
        
        // Clear player and reset state
        player = nil
        isPlaying = false
        isLoadingVideo = false
        currentTime = 0
        duration = 0
        showPlayButton = true
        
        // Clean up asset loader cache for this video
        if let urlString = videoURL,
           let url = URL(string: urlString) {
            Task {
                print("VideoPlayerView: Cleaning up asset for URL: \(urlString)")
                await VideoAssetLoader.shared.cleanupAsset(for: url)
            }
        }
        
        isInCleanupState = false
        isPlaybackStarting = false
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
    
    @MainActor
    func updateVisibility(_ isVisible: Bool) {
        self.isVisible = isVisible
        if isVisible {
            print("VideoPlayerView: Video is visible, setting as current")
            if let player = player, player.timeControlStatus != .playing {
                player.play()
                isPlaying = true
            }
        } else {
            print("VideoPlayerView: Video is not visible, pausing")
            player?.pause()
            isPlaying = false
        }
    }
    
    @MainActor
    func ensurePlayback() {
        if isVisible && !isPlaying {
            print("VideoPlayerView: Ensuring playback for visible video")
            player?.play()
            isPlaying = true
        }
    }
    
    @MainActor
    func togglePlayPause() {
        if isPlaying {
            print("Video PAUSED")
            player?.pause()
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
    
    func seekTo(time: Double) {
        let cmTime = CMTime(seconds: time, preferredTimescale: 1000)
        player?.seek(to: cmTime, toleranceBefore: .zero, toleranceAfter: .zero)
    }
} 