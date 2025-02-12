import SwiftUI
import AVKit
import AVFoundation
import FirebaseFirestore
import FirebaseAuth
import Network

#if os(iOS)

// Video Asset Loader to handle caching and streaming
actor VideoAssetLoader {
    static let shared = VideoAssetLoader()
    private let logger = Logger(component: "AssetLoader")
    
    // Add helper method to get video identifier
    private func getVideoIdentifier(from url: URL) -> String {
        if url.absoluteString.contains("archive.org/download/") {
            let components = url.absoluteString.components(separatedBy: "/download/")
            if components.count > 1 {
                let idComponents = components[1].components(separatedBy: "/")
                if let identifier = idComponents.first {
                    return "archive:\(identifier)"
                }
            }
        }
        return url.lastPathComponent
    }
    
    enum NetworkQuality {
        case poor
        case fair
        case good
    }
    
    enum PrefetchPriority {
        case high
        case medium
        case low
        
        var prefetchSize: Int {
            switch self {
            case .high: return 4 * 1024 * 1024  // 4MB
            case .medium: return 2 * 1024 * 1024 // 2MB
            case .low: return 1 * 1024 * 1024   // 1MB
            }
        }
    }
    
    enum VideoQuality {
        case auto
        case low    // 360p
        case medium // 720p
        case high   // 1080p
        
        var maxBitrate: Int {
            switch self {
            case .auto: return 0 // Will be determined dynamically
            case .low: return 500_000    // 500 Kbps for faster initial load
            case .medium: return 1_500_000 // 1.5 Mbps
            case .high: return 3_000_000   // 3 Mbps
            }
        }
        
        var preferredMaximumResolution: AVAssetReferenceRestrictions {
            switch self {
            case .auto, .high:
                return [] // No restrictions for high quality
            case .medium, .low:
                return .init(rawValue: 1 << 0) // Basic restriction level for faster loading
            }
        }
    }
    
    private let cache: URLCache
    private var assetCache = NSCache<NSURL, AVAsset>()
    private var loadingAssets: [URL: Task<AVAsset, Error>] = [:]
    private var prefetchTasks: [URL: Task<Void, Never>] = [:]
    private var preloadedData: [URL: Data] = [:]
    private var currentQuality: VideoQuality = .low // Start with low quality for faster initial load
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.cliktok.network")
    private var currentAsset: AVURLAsset?
    
    private init() {
        logger.info("🔥 Initializing with 512MB cache")
        let cacheSizeInBytes = 512 * 1024 * 1024
        self.cache = URLCache(memoryCapacity: cacheSizeInBytes / 4,
                            diskCapacity: cacheSizeInBytes,
                            diskPath: "video_cache")
        
        // Configure asset cache with larger limits
        assetCache.countLimit = 20
        assetCache.totalCostLimit = 512 * 1024 * 1024 // 512MB
        
        setupNetworkMonitoring()
    }
    
    private func checkNetworkQuality() -> NetworkQuality {
        let path = networkMonitor.currentPath
        
        switch path.status {
        case .satisfied:
            if path.isExpensive {
                return .fair
            } else if path.isConstrained {
                return .poor
            } else {
                return .good
            }
        default:
            return .poor
        }
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            // Adjust quality based on network conditions
            let quality: VideoQuality
            switch path.status {
            case .satisfied:
                if path.isExpensive {
                    quality = .medium
                } else if path.isConstrained {
                    quality = .low
                } else {
                    quality = .high
                }
            default:
                quality = .low
            }
            
            // Update quality in an actor-isolated way
            Task { [weak self] in
                await self?.updateQuality(quality)
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    private func updateQuality(_ quality: VideoQuality) {
        currentQuality = quality
        self.logger.info("🎮 Quality updated to \(quality)")
    }
    
    private func loadInitialMetadata(for asset: AVAsset) async throws {
        let startTime = Date()
        let videoId = getVideoIdentifier(from: (asset as? AVURLAsset)?.url ?? URL(fileURLWithPath: "unknown"))
        self.logger.debug("📊 [\(videoId)] Starting metadata load")
        
        // Load only essential properties first
        let essentialLoadingKeys: [String] = [
            "tracks",
            "duration",
            "playable"
        ]
        
        // Load essential properties in parallel
        try await asset.loadValues(forKeys: essentialLoadingKeys)
        
        // Load tracks in parallel with optimized loading
        async let videoTrackTask = try await asset.loadTracks(withMediaType: .video)
        async let audioTrackTask = try await asset.loadTracks(withMediaType: .audio)
        
        let (videoTracks, audioTracks) = try await (videoTrackTask, audioTrackTask)
        
        guard let videoTrack = videoTracks.first else {
            logger.error("❌ [\(videoId)] No video track found in asset")
            throw AssetError.noVideoTrack
        }
        
        // Load essential video properties in parallel
        logger.debug("🎥 [\(videoId)] Loading video track properties")
        let videoPropertiesStartTime = Date()
        
        let propertiesToLoad: [String] = ["formatDescriptions", "naturalSize", "preferredTransform"]
        try await videoTrack.loadValues(forKeys: propertiesToLoad)
        
        logger.performance("⚡️ [\(videoId)] Video properties loaded in \(Date().timeIntervalSince(videoPropertiesStartTime))s")
        
        // Load audio track properties in background with lower priority
        if let audioTrack = audioTracks.first {
            Task.detached(priority: .background) {
                self.logger.debug("🔊 [\(videoId)] Loading audio track properties in background")
                try? await audioTrack.loadValues(forKeys: ["formatDescriptions"])
            }
        }
        
        logger.success("✅ [\(videoId)] Initial metadata loaded in \(Date().timeIntervalSince(startTime))s")
    }
    
    // Helper function to implement timeouts
    private func withTimeout<T>(seconds: Double, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            // Add the main operation
            group.addTask {
                try await operation()
            }
            
            // Add a timeout task
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw NSError(domain: "VideoAssetLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Operation timed out"])
            }
            
            // Return the first completed result (or throw the first error)
            let result = try await group.next()
            
            // Cancel any remaining tasks
            group.cancelAll()
            
            return result!
        }
    }
    
    // Helper function to implement retries with exponential backoff
    private func withRetries<T>(maxAttempts: Int, operation: @escaping (_ attempt: Int) async throws -> T) async throws -> T {
        var lastError: Error?
        
        for attempt in 0..<maxAttempts {
            do {
                return try await operation(attempt)
            } catch {
                lastError = error
                if attempt < maxAttempts - 1 {
                    let delay = Double(attempt + 1) * 0.5 // 0.5s, 1s, 1.5s delay between retries
                    logger.debug("🔄 Retry \(attempt + 1) failed, waiting \(delay)s before next attempt")
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        
        throw lastError ?? NSError(domain: "VideoAssetLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "All retry attempts failed"])
    }
    
    func loadAsset(for url: URL) async throws -> AVAsset {
        let startTime = Date()
        let videoId = getVideoIdentifier(from: url)
        logger.info("🎬 [\(videoId)] Starting to load asset from URL: \(url)")
        
        // Return cached asset if available
        if let cachedAsset = await assetCache.object(forKey: url as NSURL) as? AVURLAsset {
            logger.success("✅ [\(videoId)] Found cached asset for URL: \(url)")
            currentAsset = cachedAsset
            return cachedAsset
        }
        
        // Check if there's already a loading task
        if let existingTask = loadingAssets[url] {
            logger.debug("⏳ [\(videoId)] Using existing loading task for URL: \(url)")
            return try await existingTask.value
        }
        
        logger.info("🆕 [\(videoId)] Creating new loading task for URL: \(url)")
        let task = Task<AVAsset, Error> {
            // Start with low quality for faster initial load
            let initialQuality = VideoQuality.low
            logger.debug("🎮 [\(videoId)] Creating initial streaming asset with quality: \(initialQuality)")
            
            let assetCreationStartTime = Date()
            let initialOptions: [String: Any] = [
                AVURLAssetPreferPreciseDurationAndTimingKey: false,
                "preferredPeakBitRate": initialQuality.maxBitrate,
                AVURLAssetReferenceRestrictionsKey: initialQuality.preferredMaximumResolution.rawValue,
                "AVURLAssetHTTPHeaderFieldsKey": [
                    "Range": "bytes=0-1048576",  // Request first 1MB initially for faster start
                    "icy-metadata": "0",         // Disable metadata
                    "Accept": "video/*",         // Hint at content type
                    "Cache-Control": "no-transform, max-age=31536000", // Prevent proxy compression, enable caching
                    "X-Playback-Session-Id": UUID().uuidString // Session tracking
                ],
                // Optimize loading settings
                "AVURLAssetPreferredBufferDurationKey": 2.0, // Reduced from 4.0 for faster start
                AVURLAssetAllowsCellularAccessKey: true,
                "AVURLAssetHTTPUserAgentKey": "ClikTok/1.0",
                "AVURLAssetPreferredPeakBitRateKey": 1.0, // Optimize for normal playback speed
                "AVURLAssetPrefersPreciseTimingKey": false // Prioritize performance over precise timing
            ]
            
            let asset = AVURLAsset(url: url, options: initialOptions)
            currentAsset = asset
            logger.performance("⚡️ [\(videoId)] Asset created in \(Date().timeIntervalSince(assetCreationStartTime))s")
            
            // Load only essential metadata asynchronously
            logger.info("📊 [\(videoId)] Loading minimal metadata for URL: \(url)")
            let metadataStartTime = Date()
            try await loadInitialMetadata(for: asset)
            logger.performance("⚡️ [\(videoId)] Metadata loaded in \(Date().timeIntervalSince(metadataStartTime))s")
            
            // Cache the initial quality asset
            let cacheStartTime = Date()
            await assetCache.setObject(asset, forKey: url as NSURL)
            logger.performance("⚡️ [\(videoId)] Asset cached in \(Date().timeIntervalSince(cacheStartTime))s")
            
            logger.success("✅ [\(videoId)] Initial asset prepared in \(Date().timeIntervalSince(startTime))s")
            logger.performance("📊 [\(videoId)] Performance breakdown for URL: \(url)")
            logger.performance("- Asset creation: \(Date().timeIntervalSince(assetCreationStartTime))s")
            logger.performance("- Metadata loading: \(Date().timeIntervalSince(metadataStartTime))s")
            logger.performance("- Asset caching: \(Date().timeIntervalSince(cacheStartTime))s")
            
            // Start loading higher quality in the background after playback starts
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 500_000_000) // Wait 0.5s before upgrading
                await self?.upgradeQualityIfPossible()
            }
            
            return asset
        }
        
        loadingAssets[url] = task
        
        do {
            let asset = try await task.value
            loadingAssets[url] = nil
            return asset
        } catch {
            loadingAssets[url] = nil
            logger.error("❌ [\(videoId)] Error loading asset from URL \(url): \(error.localizedDescription)")
            throw error
        }
    }
    
    private func prefetchData(for url: URL, priority: PrefetchPriority) {
        let videoId = getVideoIdentifier(from: url)
        // Cancel any existing prefetch task
        prefetchTasks[url]?.cancel()
        
        let task = Task { [weak self] in
            guard let self = self else { return }
            
            do {
                let request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
                let (data, _) = try await URLSession.shared.data(for: request)
                
                // Store only the first portion for quick start
                let prefetchSize = min(priority.prefetchSize, data.count)
                await self.updatePreloadedData(url: url, data: data.prefix(prefetchSize))
                
                logger.debug("📥 [\(videoId)] Prefetched \(prefetchSize) bytes")
            } catch {
                logger.error("❌ [\(videoId)] Prefetch failed: \(error.localizedDescription)")
            }
        }
        
        prefetchTasks[url] = task
    }
    
    private func updatePreloadedData(url: URL, data: Data.SubSequence) {
        preloadedData[url] = Data(data)
    }
    
    private func upgradeQualityIfPossible() async {
        logger.debug("Checking network conditions for quality upgrade")
        
        // Check network conditions (example implementation)
        let networkQuality = await checkNetworkQuality()
        let targetQuality = networkQuality == .good ? VideoQuality.high : VideoQuality.medium
        
        logger.info("Network quality: \(networkQuality), target quality: \(targetQuality)")
        
        do {
            let startTime = Date()
            try await upgradeAssetQuality(to: targetQuality)
            logger.success("Successfully upgraded quality to \(targetQuality) in \(Date().timeIntervalSince(startTime))s")
        } catch {
            logger.warning("Failed to upgrade quality: \(error.localizedDescription)")
        }
    }
    
    private func upgradeAssetQuality(to quality: VideoQuality) async throws {
        logger.info("Starting quality upgrade to \(quality)")
        
        guard let currentAsset = currentAsset else {
            logger.warning("No current asset to upgrade")
            return
        }
        
        let options: [String: Any] = [
            "preferredPeakBitRate": quality.maxBitrate,
            AVURLAssetReferenceRestrictionsKey: quality.preferredMaximumResolution.rawValue,
            "AVURLAssetHTTPHeaderFieldsKey": [
                "Range": "bytes=0-",  // Request full file for quality upgrade
                "icy-metadata": "0",
                "Accept": "video/*",
                "Cache-Control": "no-transform",
                "X-Playback-Session-Id": UUID().uuidString
            ]
        ]
        
        do {
            let startTime = Date()
            let upgradedAsset = AVURLAsset(url: currentAsset.url, options: options)
            try await loadInitialMetadata(for: upgradedAsset)
            
            // Update cache with higher quality version
            await assetCache.setObject(upgradedAsset, forKey: currentAsset.url as NSURL)
            logger.success("Quality upgrade completed in \(Date().timeIntervalSince(startTime))s")
            
        } catch {
            logger.error("Error during quality upgrade: \(error.localizedDescription)")
            throw error
        }
    }
    
    enum AssetError: Error {
        case timeout
        case noVideoTrack
        case invalidFormat
        case loadingFailed
        
        var localizedDescription: String {
            switch self {
            case .timeout:
                return "Asset loading timed out"
            case .noVideoTrack:
                return "No video track found in asset"
            case .invalidFormat:
                return "Invalid video format"
            case .loadingFailed:
                return "Failed to load asset"
            }
        }
    }
    
    func prefetchWithPriority(for url: URL, priority: PrefetchPriority) async {
        let videoId = getVideoIdentifier(from: url)
        logger.debug("🎬 [\(videoId)] Starting priority prefetch for URL: \(url)")
        
        // Skip if already cached or loading
        guard loadingAssets[url] == nil,
              prefetchTasks[url] == nil,
              await assetCache.object(forKey: url as NSURL) == nil else {
            logger.debug("⏭️ [\(videoId)] Asset already cached or loading for URL: \(url)")
            return
        }
        
        // Determine prefetch size based on priority and quality
        let rangeSize = priority == .high ? 4 * 1024 * 1024 : 2 * 1024 * 1024 // 4MB for high priority
        
        let task = Task {
            do {
                // Create initial asset with low quality settings for faster loading
                logger.debug("🎥 [\(videoId)] Creating initial asset during prefetch")
                let initialOptions: [String: Any] = [
                    AVURLAssetPreferPreciseDurationAndTimingKey: false,
                    "preferredPeakBitRate": VideoQuality.low.maxBitrate,
                    AVURLAssetReferenceRestrictionsKey: VideoQuality.low.preferredMaximumResolution.rawValue,
                    "AVURLAssetHTTPHeaderFieldsKey": [
                        "Range": "bytes=0-\(rangeSize)",
                        "icy-metadata": "0",
                        "Accept": "video/*",
                        "Cache-Control": "no-transform",
                        "X-Playback-Session-Id": UUID().uuidString
                    ]
                ]
                
                let asset = AVURLAsset(url: url, options: initialOptions)
                
                // Start loading essential metadata in parallel with data prefetch
                async let metadataTask = Task {
                    do {
                        logger.debug("📊 [\(videoId)] Pre-loading metadata during prefetch")
                        try await loadInitialMetadata(for: asset)
                        await assetCache.setObject(asset, forKey: url as NSURL)
                        logger.success("✅ [\(videoId)] Successfully pre-loaded metadata during prefetch")
                    } catch {
                        logger.error("❌ [\(videoId)] Failed to pre-load metadata: \(error.localizedDescription)")
                        throw error
                    }
                }
                
                // Prefetch initial data range
                let session = URLSession.shared
                var request = URLRequest(url: url)
                request.setValue("bytes=0-\(rangeSize)", forHTTPHeaderField: "Range")
                request.cachePolicy = .returnCacheDataElseLoad
                
                logger.debug("📥 [\(videoId)] Downloading initial \(rangeSize/1024)KB from URL: \(url)")
                let (data, response) = try await session.data(for: request)
                
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode == 206 {
                    await updatePreloadedData(url: url, data: data[...])
                    logger.success("✅ [\(videoId)] Successfully prefetched \(data.count) bytes from URL: \(url)")
                    
                    // Wait for metadata loading to complete
                    _ = try await metadataTask.value
                    
                    // If high priority, start loading the rest of the video
                    if priority == .high {
                        Task {
                            logger.debug("🔄 [\(videoId)] Starting full asset load for high priority video")
                            try await loadAsset(for: url)
                        }
                    }
                } else {
                    logger.warning("⚠️ [\(videoId)] Server doesn't support range requests for URL: \(url), falling back to full load")
                    // Wait for metadata loading to complete
                    _ = try await metadataTask.value
                }
            } catch {
                logger.error("❌ [\(videoId)] Prefetch failed for URL \(url): \(error.localizedDescription)")
            }
        }
        
        prefetchTasks[url] = task
    }
    
    func cleanupAsset(for url: URL) {
        let videoId = getVideoIdentifier(from: url)
        logger.debug("🧹 [\(videoId)] Cleaning up asset for URL: \(url)")
        assetCache.removeObject(forKey: url as NSURL)
        preloadedData.removeValue(forKey: url)
        loadingAssets[url]?.cancel()
        loadingAssets[url] = nil
        prefetchTasks[url]?.cancel()
        prefetchTasks[url] = nil
        cache.removeCachedResponse(for: URLRequest(url: url))
        logger.success("✅ [\(videoId)] Cleanup complete for URL: \(url)")
    }
    
    func clearCache() {
        logger.debug("🗑️ Clearing all caches")
        assetCache.removeAllObjects()
        preloadedData.removeAll()
        cache.removeAllCachedResponses()
        logger.success("✅ Cache cleared")
    }
    
    deinit {
        logger.debug("🔥 VideoAssetLoader deinitializing")
        networkMonitor.cancel()
        for task in prefetchTasks.values {
            task.cancel()
        }
    }
}

// Video Controls Overlay
struct VideoControlsOverlay: View {
    let showControls: Bool
    let isPlaying: Bool
    let togglePlayPause: () -> Void
    
    var body: some View {
        Button(action: {
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
    let video: Video
    let isMuted: Bool
    let viewCount: Int
    @Binding var showTipBubble: Bool
    @Binding var showTippedText: Bool
    @Binding var showAddFundsAlert: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    let toggleMute: () -> Void
    @State private var isHeartFilled = false
    @State private var localTotalTips: Int
    @State private var heartOpacity: Double = 1.0
    @State private var heartScale: CGFloat = 1.0
    
    // Lazy load TipViewModel
    private var tipViewModel: TipViewModel {
        TipViewModel.shared
    }
    
    init(totalTips: Int, video: Video, isMuted: Bool, viewCount: Int, showTipBubble: Binding<Bool>, showTippedText: Binding<Bool>, showAddFundsAlert: Binding<Bool>, showError: Binding<Bool>, errorMessage: Binding<String>, toggleMute: @escaping () -> Void) {
        self.totalTips = totalTips
        self.video = video
        self.isMuted = isMuted
        self.viewCount = viewCount
        self._showTipBubble = showTipBubble
        self._showTippedText = showTippedText
        self._showAddFundsAlert = showAddFundsAlert
        self._showError = showError
        self._errorMessage = errorMessage
        self.toggleMute = toggleMute
        self._localTotalTips = State(initialValue: totalTips)
    }
    
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
                                        heartOpacity = 1.0
                                        heartScale = 1.3
                                        localTotalTips += 1  // Increment immediately for better UX
                                    }
                                    
                                    // Reset scale after the spring animation
                                    withAnimation(.easeOut(duration: 0.2).delay(0.3)) {
                                        heartScale = 1.0
                                    }
                                    
                                    guard let videoId = video.id else { return }
                                    try await tipViewModel.sendMinimumTip(receiverID: video.userID, videoID: videoId)
                                    
                                    withAnimation {
                                        showTipBubble = true
                                        showTippedText = true
                                    }
                                    
                                    // Start fade out animations
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                        withAnimation(.easeOut(duration: 0.5)) {
                                            showTipBubble = false
                                            showTippedText = false
                                            heartOpacity = 0.3
                                        }
                                        
                                        // Reset heart to unfilled state after fade
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            withAnimation(.easeOut(duration: 0.3)) {
                                                isHeartFilled = false
                                                heartOpacity = 1.0  // Return to full opacity
                                            }
                                        }
                                    }
                                } catch PaymentError.insufficientFunds {
                                    withAnimation {
                                        localTotalTips -= 1  // Revert if payment fails
                                        isHeartFilled = false
                                        heartOpacity = 0.3
                                        heartScale = 1.0
                                    }
                                    showAddFundsAlert = true
                                } catch {
                                    withAnimation {
                                        localTotalTips -= 1  // Revert if payment fails
                                        isHeartFilled = false
                                        heartOpacity = 0.3
                                        heartScale = 1.0
                                    }
                                    showError = true
                                    errorMessage = error.localizedDescription
                                }
                            }
                        }) {
                            VStack(spacing: 4) {
                                Image(systemName: "heart\(isHeartFilled ? ".fill" : "")")
                                    .resizable()
                                    .frame(width: 32, height: 32)
                                    .foregroundColor(isHeartFilled ? .red : .gray)
                                    .opacity(heartOpacity)
                                    .scaleEffect(heartScale)
                                    .shadow(radius: 2)
                                
                                Text("\(localTotalTips)¢")
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
                            .transition(.opacity)
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
                Text("\(viewCount)")
                    .foregroundColor(.gray)
                    .font(.system(size: 14, design: .monospaced))
                    .shadow(radius: 2)
            }
            .offset(x: 40, y: 10)
        }
        .padding(.trailing)
        .onChange(of: totalTips) { newValue in
            localTotalTips = newValue
        }
    }
}

// Video Info Section
struct VideoInfoSection: View {
    let video: Video
    let creator: User?
    let geometry: GeometryProxy
    let totalTips: Int
    let isMuted: Bool
    let showCreator: Bool
    let viewCount: Int
    @Binding var showTipBubble: Bool
    @Binding var showTippedText: Bool
    @Binding var showAddFundsAlert: Bool
    @Binding var showError: Bool
    @Binding var errorMessage: String
    let toggleMute: () -> Void
    
    // Lazy load TipViewModel
    private var tipViewModel: TipViewModel {
        TipViewModel.shared
    }
    
    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            RetroVideoInfo(
                title: video.caption.cleaningHTMLTags(),
                description: (video.description ?? "").cleaningHTMLTags(),
                hashtags: video.hashtags,
                creator: showCreator ? creator : nil,
                showCreator: showCreator
            )
            .frame(maxWidth: geometry.size.width * 0.85, alignment: .leading)
            
            Spacer(minLength: 0)
            
            VideoControlButtons(
                totalTips: totalTips,
                video: video,
                isMuted: isMuted,
                viewCount: viewCount,
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
// VideoPlayerViewModel has been moved to its own file

// MARK: - Main Video Player View Components
struct VideoPlayerView: View {
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @StateObject private var playerViewModel = VideoPlayerViewModel()
    @Environment(\.dismiss) private var dismiss
    private let logger = Logger(component: "VideoPlayerView")
    
    let video: Video
    let showBackButton: Bool
    let showCreator: Bool
    @Binding var clearSearchOnDismiss: Bool
    @Binding var isVisible: Bool
    
    // Add viewing time tracking
    @State private var viewingStartTime: Date?
    @State private var hasUpdatedStats = false
    @State private var currentViewCount: Int
    
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
    
    // Lazy load TipViewModel
    private var tipViewModel: TipViewModel {
        TipViewModel.shared
    }
    
    let onPrefetch: (([Video]) -> Void)?
    
    init(video: Video, showBackButton: Bool = false, clearSearchOnDismiss: Binding<Bool> = .constant(false), isVisible: Binding<Bool>, showCreator: Bool = true, onPrefetch: (([Video]) -> Void)? = nil) {
        self.video = video
        self.showBackButton = showBackButton
        self.showCreator = showCreator
        self._clearSearchOnDismiss = clearSearchOnDismiss
        self._isVisible = isVisible
        self.onPrefetch = onPrefetch
        self._currentViewCount = State(initialValue: video.views)
        
        // Configure audio session once at init
        Task { [self] in
            do {
                try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try AVAudioSession.sharedInstance().setActive(true)
                logger.debug("🎧 Audio session configured successfully for video: \(video.stableId)")
            } catch {
                logger.error("❌ Failed to set audio session category for video \(video.stableId): \(error)")
            }
        }
    }
    
    private func setupVideo() {
        logger.info("🎥 Setting up video: \(video.stableId) with URL: \(video.videoURL)")
        playerViewModel.setVideo(url: video.videoURL, isVisible: isVisible, hideControls: {
            withAnimation {
                showControls = false
                logger.debug("🎮 Controls hidden for video \(video.stableId) - auto-play complete")
            }
        })
        Task {
            // Load video metadata, creator info, and stats in parallel
            logger.debug("🎬 Starting parallel loading of video data for \(video.stableId)")
            
            async let videoLoadTask = playerViewModel.loadAndPlayVideo()
            async let creatorLoadTask = loadCreatorIfNeeded()
            async let statsLoadTask = loadInitialStats()
            
            // Wait for all tasks to complete
            try await videoLoadTask
            await creatorLoadTask
            await statsLoadTask
            
            // Load balance and tip history
            logger.debug("💰 Loading balance and tip history for video \(video.stableId)")
            await tipViewModel.loadBalance()
            await tipViewModel.loadTipHistory()
            
            // Update tip count
            if let videoId = video.id {
                totalTips = tipViewModel.sentTips.filter { $0.videoID == videoId }.count
                logger.debug("💝 Total tips for video \(video.stableId): \(totalTips)")
            } else {
                logger.warning("⚠️ No Firestore ID available for video: \(video.stableId)")
            }
        }
    }
    
    private func loadCreatorIfNeeded() async {
        if creator == nil {
            logger.debug("👤 Fetching creator information for video \(video.stableId)")
            await feedViewModel.fetchCreators(for: [video])
            creator = feedViewModel.getCreator(for: video)
            if let creator = creator {
                logger.debug("👤 Creator loaded for video \(video.stableId): \(creator.displayName)")
            }
        }
    }
    
    private func loadInitialStats() async {
        do {
            logger.debug("📊 Loading initial stats for video \(video.stableId)")
            let views = try await feedViewModel.fetchVideoStats(for: video)
            await MainActor.run {
                currentViewCount = views + 1  // Optimistically add 1 to the view count
                logger.debug("📊 Initial view count loaded and incremented: \(views) + 1")
            }
        } catch {
            logger.error("❌ Failed to load initial stats: \(error.localizedDescription)")
        }
    }
    
    private func handleVisibilityChange(_ newValue: Bool) {
        logger.debug("👁️ Visibility changed to \(newValue) for video \(video.stableId)")
        if newValue {
            // Start tracking viewing time when video becomes visible
            if viewingStartTime == nil {
                viewingStartTime = Date()
                logger.debug("⏱️ Started view tracking at \(viewingStartTime!)")
            }
            
            // Immediately update player visibility for autoplay
            playerViewModel.updateVisibility(true)
            
            // Ensure we don't clean up too early
            Task {
                try? await Task.sleep(nanoseconds: 100_000_000)  // 0.1 second delay
                if isVisible {  // Reconfirm visibility after delay
                    playerViewModel.ensurePlayback()
                }
            }
        } else {
            // Reset viewing time tracking when video becomes invisible
            if viewingStartTime != nil {
                logger.debug("⏱️ Resetting view tracking - video became invisible")
                viewingStartTime = nil
            }
            playerViewModel.updateVisibility(false)
        }
    }
    
    private func updateVideoStats() async {
        do {
            logger.info("📊 Starting view count update for video: \(video.stableId)")
            logger.debug("Current view count before Firebase update: \(currentViewCount)")
            logger.debug("Video type: \(video.isArchiveVideo ? "Archive" : "Regular")")
            logger.debug("Stats document ID: \(video.statsDocumentId)")
            
            // Update Firebase
            try await feedViewModel.updateVideoStats(video: video)
            hasUpdatedStats = true
            
            // No need to update the UI since we already incremented optimistically
            logger.success("✅ View count updated successfully in Firebase")
        } catch {
            // If Firebase update fails, revert the optimistic update
            await MainActor.run {
                currentViewCount -= 1
                logger.debug("📊 Reverted optimistic update due to error")
            }
            logger.error("❌ Failed to update view count: \(error.localizedDescription)")
        }
    }
    
    private func handleEditSheetChange(_ newValue: Bool) {
        if newValue {
            logger.debug("✏️ Edit sheet opened for video \(video.stableId), pausing playback")
            playerViewModel.player?.pause()
            playerViewModel.isPlaying = false
        } else {
            logger.debug("✏️ Edit sheet closed for video \(video.stableId), resuming playback")
            playerViewModel.player?.play()
            playerViewModel.isPlaying = true
            Task {
                await feedViewModel.loadInitialVideos()
            }
        }
    }
    
    private func resetControlsTimer() {
        guard !isResettingControls else { return }
        isResettingControls = true
        
        controlsTimer?.invalidate()
        
        withAnimation {
            showControls = true
            logger.debug("🎮 Controls shown - resetControlsTimer()")
        }
        
        lastControlReset = Date()
        
        if playerViewModel.isPlaying && !isDraggingProgress {
            controlsTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: false) { _ in
                if playerViewModel.isPlaying && !isDraggingProgress {
                    withAnimation {
                        showControls = false
                        logger.debug("🎮 Controls hidden - timer expired")
                    }
                }
                isResettingControls = false
            }
        } else {
            isResettingControls = false
        }
    }
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Black background
                Color.black.edgesIgnoringSafeArea(.all)
                
                // Main video player content
                MainVideoContent(
                    player: playerViewModel.player,
                    isLoadingVideo: playerViewModel.isLoadingVideo,
                    showControls: $showControls,
                    playerViewModel: playerViewModel,
                    isDraggingProgress: isDraggingProgress,
                    resetControlsTimer: resetControlsTimer,
                    geometry: geometry
                )
                
                // UI Overlay
                VideoOverlayContent(
                    showBackButton: showBackButton,
                    video: video,
                    creator: creator,
                    geometry: geometry,
                    totalTips: totalTips,
                    tipViewModel: tipViewModel,
                    playerViewModel: playerViewModel,
                    showCreator: showCreator,
                    currentViewCount: currentViewCount,
                    showTipBubble: $showTipBubble,
                    showTippedText: $showTippedText,
                    showAddFundsAlert: $showAddFundsAlert,
                    showError: $showError,
                    clearSearchOnDismiss: $clearSearchOnDismiss,
                    showEditSheet: $showEditSheet,
                    showDeleteAlert: $showDeleteAlert,
                    onDismiss: {
                        logger.debug("Dismissing video player")
                        playerViewModel.cleanupPlayer()
                        clearSearchOnDismiss = true
                        dismiss()
                    }
                )
                
                // Status bar
                RetroStatusBar()
                    .frame(height: 44)
            }
            .navigationBarHidden(true)
            .edgesIgnoringSafeArea(.all)
            .statusBar(hidden: true)  // Hide the system status bar
        }
        .onAppear {
            logger.debug("VideoPlayerView appeared")
            setupVideo()
        }
        .onDisappear {
            logger.debug("VideoPlayerView disappearing, cleaning up")
            playerViewModel.cleanupPlayer()
        }
        .onChange(of: isVisible, perform: handleVisibilityChange)
        .onChange(of: showEditSheet, perform: handleEditSheetChange)
        .onChange(of: playerViewModel.isPlaying) { isPlaying in
            if isPlaying && !hasUpdatedStats {
                Task {
                    await updateVideoStats()
                }
            }
        }
        .onReceive(tipViewModel.$sentTips) { newTips in
            if let videoId = video.id {
                totalTips = newTips.filter { $0.videoID == videoId }.count
                logger.debug("Updated total tips: \(totalTips)")
            }
        }
        .sheet(isPresented: $showEditSheet) {
            VideoEditView(video: video, isPresented: $showEditSheet)
                .environmentObject(feedViewModel)
        }
        .alert("Add Funds", isPresented: $showAddFundsAlert) {
            Button("Add Funds") { showWallet = true }
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
                        logger.debug("Deleting video: \(video.stableId)")
                        try await feedViewModel.deleteVideo(video)
                        playerViewModel.cleanupPlayer()
                        dismiss()
                        logger.debug("Video deleted successfully")
                    } catch {
                        logger.error("Failed to delete video: \(error)")
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

// MARK: - Supporting Views
private struct MainVideoContent: View {
    let player: AVPlayer?
    let isLoadingVideo: Bool
    @Binding var showControls: Bool
    @ObservedObject var playerViewModel: VideoPlayerViewModel
    let isDraggingProgress: Bool
    let resetControlsTimer: () -> Void
    let geometry: GeometryProxy
    
    var body: some View {
        Group {
            if let player = player {
                VideoPlayer(player: player)
                    .edgesIgnoringSafeArea(.all)
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .overlay {
                        VideoControlsOverlayContainer(
                            showControls: $showControls,
                            playerViewModel: playerViewModel,
                            isDraggingProgress: isDraggingProgress,
                            resetControlsTimer: resetControlsTimer,
                            player: player,
                            geometry: geometry
                        )
                    }
            } else if isLoadingVideo {
                ProgressView()
                    .tint(.white)
            }
        }
    }
}

private struct VideoOverlayContent: View {
    let showBackButton: Bool
    let video: Video
    let creator: User?
    let geometry: GeometryProxy
    let totalTips: Int
    let tipViewModel: TipViewModel
    @ObservedObject var playerViewModel: VideoPlayerViewModel
    let showCreator: Bool
    let currentViewCount: Int
    @Binding var showTipBubble: Bool
    @Binding var showTippedText: Bool
    @Binding var showAddFundsAlert: Bool
    @Binding var showError: Bool
    @Binding var clearSearchOnDismiss: Bool
    @Binding var showEditSheet: Bool
    @Binding var showDeleteAlert: Bool
    let onDismiss: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            if showBackButton {
                HStack {
                    Button(action: onDismiss) {
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
                .padding(.top, 44)
            } else if video.userID == Auth.auth().currentUser?.uid {
                HStack {
                    Spacer()
                    VideoMenuButton(showEditSheet: $showEditSheet, showDeleteAlert: $showDeleteAlert)
                }
                .padding(.top, 44)
            }
            
            Spacer()
            
            VideoInfoSection(
                video: video,
                creator: creator,
                geometry: geometry,
                totalTips: totalTips,
                isMuted: playerViewModel.isMuted,
                showCreator: showCreator,
                viewCount: currentViewCount,
                showTipBubble: $showTipBubble,
                showTippedText: $showTippedText,
                showAddFundsAlert: $showAddFundsAlert,
                showError: $showError,
                errorMessage: $playerViewModel.errorMessage,
                toggleMute: playerViewModel.toggleMute
            )
        }
    }
}

// Video Controls Container
private struct VideoControlsOverlayContainer: View {
    @Binding var showControls: Bool
    @ObservedObject var playerViewModel: VideoPlayerViewModel
    let isDraggingProgress: Bool
    let resetControlsTimer: () -> Void
    let player: AVPlayer
    let geometry: GeometryProxy
    private let logger = Logger(component: "VideoControlsContainer")
    
    var body: some View {
        ZStack {
            // Full-screen tap gesture area
            Color.black.opacity(0.01)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation {
                        showControls.toggle()
                        if showControls {
                            logger.debug("🎮 Controls toggled, showing controls")
                            resetControlsTimer()
                        } else {
                            logger.debug("🎮 Controls toggled, hiding controls")
                        }
                    }
                }
                .allowsHitTesting(!playerViewModel.showPlayButton)

            // Controls layer
            VStack {
                Spacer()
                
                // Center container for play/pause button
                ZStack {
                    VideoControlsOverlay(
                        showControls: showControls || playerViewModel.showPlayButton,
                        isPlaying: playerViewModel.isPlaying,
                        togglePlayPause: playerViewModel.togglePlayPause
                    )
                    .allowsHitTesting(true)
                    .zIndex(100)
                }
                .frame(maxWidth: .infinity, maxHeight: 100)
                .contentShape(Rectangle())
                .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                
                Spacer()
                
                // Progress bar
                VideoProgressOverlay(
                    duration: playerViewModel.duration,
                    showControls: showControls,
                    currentTime: $playerViewModel.currentTime,
                    isDraggingProgress: .constant(isDraggingProgress),
                    isPlaying: playerViewModel.isPlaying,
                    player: player,
                    resetControlsTimer: resetControlsTimer
                )
                .allowsHitTesting(true)
            }
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
    private let logger = Logger(component: "ProgressBar")
    
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
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let ratio = max(0, min(gesture.location.x / geometry.size.width, 1))
                        let newValue = total * Double(ratio)
                        isDragging = true
                        logger.debug("🎮 Progress drag changed: \(String(format: "%.2f", newValue))s")
                        onChanged(newValue)
                    }
                    .onEnded { gesture in
                        let ratio = max(0, min(gesture.location.x / geometry.size.width, 1))
                        let newValue = total * Double(ratio)
                        logger.debug("🎮 Progress drag ended: \(String(format: "%.2f", newValue))s")
                        onEnded(newValue)
                        isDragging = false
                    }
            )
        }
        .frame(height: 20)
    }
}

#endif
