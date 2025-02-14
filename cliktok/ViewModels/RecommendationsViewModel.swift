import SwiftUI
import FirebaseFirestore

@MainActor
class RecommendationsViewModel: ObservableObject {
    @Published var interests: [String] = []
    @Published var topCategories: [String] = []
    @Published var recommendedVideos: [Video] = []
    @Published var tippedVideos: [Video] = []
    @Published var visibleTippedVideos: [Video] = []
    @Published var currentStartIndex = 0
    @Published var explanation: String = ""
    @Published var isLoading = false
    @Published var error: String?
    
    private let recommendationsService = RecommendationsService.shared
    private let tipViewModel = TipViewModel.shared
    private let db = Firestore.firestore()
    private var scrollTimer: Timer?
    private let maxVisibleVideos = 8
    
    private func updateVisibleVideos() {
        let endIndex = min(currentStartIndex + maxVisibleVideos, tippedVideos.count)
        visibleTippedVideos = Array(tippedVideos[currentStartIndex..<endIndex])
    }
    
    @objc private func scrollToNextVideo() {
        guard tippedVideos.count > maxVisibleVideos else { return }
        
        Task { @MainActor in
            currentStartIndex = (currentStartIndex + 1) % (tippedVideos.count - maxVisibleVideos + 1)
            updateVisibleVideos()
        }
    }
    
    func startScrollingVideos() {
        guard tippedVideos.count > maxVisibleVideos else {
            visibleTippedVideos = tippedVideos
            return
        }
        
        updateVisibleVideos()
        
        // Create a timer that updates the visible videos every 2 seconds
        scrollTimer?.invalidate()
        scrollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.scrollToNextVideo()
        }
    }
    
    func stopScrolling() {
        scrollTimer?.invalidate()
        scrollTimer = nil
    }
    
    func loadRecommendations() async {
        isLoading = true
        error = nil
        tippedVideos = []
        visibleTippedVideos = []
        currentStartIndex = 0
        stopScrolling()
        
        do {
            let tips = tipViewModel.sentTips
            guard !tips.isEmpty else {
                error = "No tipping history found. Tip some videos to get personalized recommendations!"
                isLoading = false
                return
            }
            
            // Create a set to track unique video IDs
            var processedVideoIds = Set<String>()
            
            // First fetch and set the tipped videos so they show during loading
            for tip in tips {
                // Skip if we've already processed this video
                guard !processedVideoIds.contains(tip.videoID) else { continue }
                processedVideoIds.insert(tip.videoID)
                
                if tip.videoID.hasPrefix("archive_") {
                    let archiveId = String(tip.videoID.dropFirst(8))
                    let video = Video(
                        id: tip.videoID,
                        archiveIdentifier: archiveId,
                        userID: "archive_user",
                        videoURL: InternetArchiveAPI.getVideoURL(identifier: archiveId),
                        thumbnailURL: InternetArchiveAPI.getThumbnailURL(identifier: archiveId).absoluteString,
                        caption: archiveId.replacingOccurrences(of: "_", with: " ")
                            .replacingOccurrences(of: "-", with: " ")
                            .capitalized,
                        description: nil,
                        hashtags: ["archive"],
                        createdAt: tip.timestamp,
                        likes: 0,
                        views: 0
                    )
                    tippedVideos.append(video)
                    startScrollingVideos()
                    // Add a small delay between each video
                    try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                } else {
                    do {
                        let doc = try await db.collection("videos").document(tip.videoID).getDocument()
                        if let video = try? doc.data(as: Video.self) {
                            tippedVideos.append(video)
                            startScrollingVideos()
                            // Add a small delay between each video
                            try? await Task.sleep(nanoseconds: 300_000_000) // 0.3 seconds
                        }
                    } catch {
                        print("Error fetching video \(tip.videoID): \(error)")
                    }
                }
            }
            
            let summary = try await recommendationsService.generateRecommendations(from: tips)
            
            // Filter out any duplicate recommended videos
            let uniqueRecommendedVideos = summary.recommendedVideos.filter { video in
                guard let videoId = video.id else { return false }
                return !processedVideoIds.contains(videoId)
            }
            
            interests = summary.interests
            topCategories = summary.topCategories
            recommendedVideos = uniqueRecommendedVideos
            explanation = summary.explanation
        } catch {
            self.error = "Failed to load recommendations: \(error.localizedDescription)"
        }
        
        isLoading = false
        stopScrolling()
    }
    
    deinit {
        // Since deinit is nonisolated, we need to handle timer cleanup differently
        scrollTimer?.invalidate()
        scrollTimer = nil
        
        // Schedule any main actor work for later since we can't await in deinit
        Task { @MainActor in
            // Clean up any other main actor resources if needed
        }
    }
} 