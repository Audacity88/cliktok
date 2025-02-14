import SwiftUI
import AVKit
import Foundation
import FirebaseAuth
import os

private let logger = Logger(component: "UnifiedVideoView")

private extension String {
    func optimizedVideoURL() -> String {
        if self.hasSuffix(".m4v") {
            let mp4URL = self.replacingOccurrences(of: ".m4v", with: ".mp4")
            print("UnifiedVideoView: Attempting to use MP4 version: \(mp4URL)")
            return mp4URL
        }
        return self
    }
}

struct RetroVideoInfo: View {
    let title: String
    let description: String?
    let hashtags: [String]
    let creator: User?
    let showCreator: Bool
    @State private var isDescriptionExpanded = false
    private let maxCharacters = 100
    
    init(title: String, description: String? = nil, hashtags: [String], creator: User? = nil, showCreator: Bool = false) {
        self.title = title
        self.description = description
        self.hashtags = hashtags
        self.creator = creator
        self.showCreator = showCreator
    }
    
    private var shouldTruncate: Bool {
        guard let description = description else { return false }
        return description.count > maxCharacters
    }
    
    private var displayedDescription: String {
        guard let description = description else { return "" }
        if !isDescriptionExpanded && shouldTruncate {
            let index = description.index(description.startIndex, offsetBy: maxCharacters)
            return String(description[..<index]) + "..."
        }
        return description
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Title
            Text(title)
                .font(.system(.footnote, design: .monospaced))
                .foregroundColor(.green)
            
            // Hashtags
            Text(hashtags.map { "#\($0)" }.joined(separator: " "))
                .font(.system(.caption2, design: .monospaced))
                .foregroundColor(.gray)
            
            // Description
            if let description = description {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayedDescription)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.green.opacity(0.8))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.trailing, -80)
                    
                    if shouldTruncate {
                        Button(action: {
                            withAnimation {
                                isDescriptionExpanded.toggle()
                            }
                        }) {
                            Text(isDescriptionExpanded ? "Show less" : "Show more")
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundColor(.green)
                        }
                        .padding(.top, 2)
                    }
                }
            }
            
            // Creator Profile
            if showCreator, let creator = creator {
                HStack(alignment: .center, spacing: 8) {
                    NavigationLink(destination: ProfileView(userId: creator.id)) {
                        ProfileImageView(imageURL: creator.profileImageURL, size: 32)
                    }
                    
                    Text(creator.displayName)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.white)
                }
                .padding(.top, 2)
            }
        }
        .padding(.horizontal)
        .padding(.bottom, -12)
        .padding(.top, 16)
    }
}

struct VideoList: View {
    let videos: [Video]
    let currentIndex: Int
    let geometry: GeometryProxy
    let viewModel: VideoFeedViewModel
    @Binding var selectedIndex: Int
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(videos.enumerated()), id: \.element.stableId) { index, video in
                ZStack {
                    VideoPlayerView(
                        video: video,
                        showBackButton: false,
                        clearSearchOnDismiss: .constant(false),
                        isVisible: .constant(index == selectedIndex),
                        showCreator: video.userID != "archive_user"
                    )
                    .environmentObject(viewModel)
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .rotationEffect(.degrees(-90))
                .tag(index)
                .task(id: index) {
                    guard index == selectedIndex else {
                        // Immediately cleanup video when it's no longer selected
                        if let url = URL(string: video.videoURL) {
                            print("UnifiedVideoView: Immediate cleanup of video at index \(index)")
                            Task {
                                await VideoAssetLoader.shared.cleanupAsset(for: url)
                            }
                        }
                        return
                    }
                    print("UnifiedVideoView: Video \(index) appeared")
                    
                    if index >= videos.count - 2 {
                        print("UnifiedVideoView: Approaching end, loading more videos...")
                        await viewModel.loadMoreVideos()
                    }
                }
                .overlay(alignment: .bottom) {
                    if viewModel.isLoading && index >= videos.count - 2 {
                        ProgressView()
                            .padding()
                            .background(Color.black.opacity(0.5))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .frame(
            width: geometry.size.height,
            height: geometry.size.width
        )
        .rotationEffect(.degrees(90), anchor: .topLeading)
        .offset(
            x: geometry.size.width,
            y: geometry.size.width/2 - geometry.size.height/2
        )
        .tabViewStyle(.page(indexDisplayMode: .never))
        .ignoresSafeArea()
    }
}

struct UnifiedVideoView: View {
    @StateObject private var archiveViewModel = ArchiveVideoViewModel()
    @State private var currentIndex = 0
    @State private var isPrefetching = false
    @State private var visibleRange: Range<Int> = 0..<3
    @State private var showCollections = false
    @State private var mode: ViewMode
    @State private var searchQuery: String = ""
    @State private var isSearching = false
    @State private var dragOffset = CGSize.zero
    @State private var opacity: Double = 1.0
    @Environment(\.dismiss) private var dismiss
    
    // Use ObservedObject for externally provided view model
    @ObservedObject var feedViewModel: VideoFeedViewModel
    
    enum ViewMode {
        case feed
        case archive
        case search
        case grid
    }
    
    let startingVideo: Video?
    let fixedVideos: [Video]?
    var showBackButton: Bool
    @Binding var clearSearchOnDismiss: Bool
    
    init(mode: ViewMode = .feed, searchQuery: String = "") {
        self._mode = State(initialValue: mode)
        self._searchQuery = State(initialValue: searchQuery)
        self.startingVideo = nil
        self.fixedVideos = nil
        self.showBackButton = false
        self._clearSearchOnDismiss = .constant(false)
        self.feedViewModel = VideoFeedViewModel()
    }
    
    init(mode: ViewMode = .grid, videos: [Video]? = nil, startingVideo: Video? = nil, showBackButton: Bool = false, clearSearchOnDismiss: Binding<Bool> = .constant(false), feedViewModel: VideoFeedViewModel) {
        self._mode = State(initialValue: mode)
        self._searchQuery = State(initialValue: "")
        self.startingVideo = startingVideo
        self.fixedVideos = videos
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
        self.feedViewModel = feedViewModel
        
        if let videos = videos, let startingVideo = startingVideo,
           let index = videos.firstIndex(where: { $0.stableId == startingVideo.stableId }) {
            self._currentIndex = State(initialValue: index)
        } else {
            self._currentIndex = State(initialValue: 0)
        }
    }
    
    private var currentVideos: [Video] {
        switch mode {
        case .feed:
            return feedViewModel.videos
        case .archive:
            guard let collection = archiveViewModel.selectedCollection else { return [] }
            return collection.videos.map { archiveVideo in
                Video(
                    id: nil,
                    archiveIdentifier: archiveVideo.identifier,
                    userID: "archive_user",
                    videoURL: archiveVideo.videoURL.optimizedVideoURL(),
                    thumbnailURL: InternetArchiveAPI.getThumbnailURL(identifier: archiveVideo.identifier).absoluteString,
                    caption: archiveVideo.title,
                    description: archiveVideo.description,
                    hashtags: ["archive"],
                    createdAt: Date(),
                    likes: 0,
                    views: 0
                )
            }
        case .search:
            return feedViewModel.searchResults
        case .grid:
            return fixedVideos ?? []
        }
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                ZStack {
                    Color.black
                        .opacity(opacity)
                        .edgesIgnoringSafeArea(.all)
                    
                    if isLoading {
                        LoadingView()
                    } else if !currentVideos.isEmpty {
                        VideoList(
                            videos: currentVideos,
                            currentIndex: currentIndex,
                            geometry: geometry,
                            viewModel: feedViewModel,
                            selectedIndex: $currentIndex
                        )
                    } else {
                        VStack {
                            Text(emptyStateMessage)
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                            if mode == .archive {
                                Button("Select Collection") {
                                    showCollections = true
                                }
                                .buttonStyle(.bordered)
                                .tint(.green)
                            }
                        }
                    }
                }
                .onChange(of: currentIndex) { oldValue, newValue in
                    print("UnifiedVideoView: Switched from video \(oldValue) to \(newValue)")
                    Task {
                        await handleVideoChange(newValue)
                        await prefetchUpcomingVideos(currentIndex: newValue)
                        cleanupDistantVideos(currentIndex: newValue)
                    }
                }
                .onChange(of: searchQuery) { _, newQuery in
                    guard mode == .search else { return }
                    logger.debug("Search query changed to: \(newQuery)")
                    Task {
                        logger.debug("Starting search for: \(newQuery)")
                        isSearching = true
                        if newQuery.hasPrefix("#") {
                            logger.debug("Performing hashtag search")
                            await feedViewModel.searchVideos(hashtag: String(newQuery.dropFirst()))
                        } else {
                            logger.debug("Performing text search")
                            await feedViewModel.searchByText(newQuery)
                        }
                        logger.debug("Search completed with \(feedViewModel.searchResults.count) results")
                        isSearching = false
                    }
                }
                .task {
                    logger.debug("UnifiedVideoView task started")
                    await handleInitialLoad()
                }
                .onAppear {
                    logger.debug("UnifiedVideoView appeared with mode: \(mode)")
                    // Only show collections if explicitly in archive mode
                    if mode == .archive && showCollections {
                        logger.debug("Preloading archive collections")
                        archiveViewModel.preloadCollections()
                    }
                }
                .onDisappear {
                    logger.debug("UnifiedVideoView disappeared")
                    if mode == .archive {
                        logger.debug("Canceling archive preloading")
                        archiveViewModel.cancelPreloading()
                    }
                }
            }
            
            // Navigation controls
            if shouldShowNavigation {
                HStack(spacing: 16) {
                    // Collections button for archive mode
                    if mode == .archive {
                        Button(action: {
                            showCollections = true
                        }) {
                            Image(systemName: "square.grid.2x2")
                                .font(.system(size: 24))
                                .foregroundColor(.green)
                                .frame(width: 44, height: 44)
                                .background(Color.black.opacity(0.5))
                                .clipShape(Circle())
                        }
                    }
                }
                .padding(.top, 50)
                .padding(.trailing, 16)
            }
        }
        .sheet(isPresented: $showCollections) {
            ArchiveCollectionGalleryView(selectedCollection: $archiveViewModel.selectedCollection)
                .environmentObject(archiveViewModel)
        }
        .if(mode == .grid) { view in
            view
                .navigationBarBackButtonHidden(true)
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            clearSearchOnDismiss = true
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                                .imageScale(.large)
                        }
                    }
                }
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if abs(gesture.translation.width) > abs(gesture.translation.height) {
                                dragOffset = gesture.translation
                                let dragPercentage = min(1, abs(gesture.translation.width) / 200)
                                opacity = 1 - dragPercentage
                            }
                        }
                        .onEnded { gesture in
                            let threshold: CGFloat = 100
                            if gesture.translation.width > threshold {
                                clearSearchOnDismiss = true
                                withAnimation(.easeOut(duration: 0.3)) {
                                    dragOffset = CGSize(width: UIScreen.main.bounds.width, height: 0)
                                    opacity = 0
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    dismiss()
                                }
                            } else {
                                withAnimation(.interactiveSpring()) {
                                    dragOffset = .zero
                                    opacity = 1
                                }
                            }
                        }
                )
                .offset(x: dragOffset.width)
        }
        .statusBar(hidden: true)
    }
    
    private var isLoading: Bool {
        switch mode {
        case .feed:
            return feedViewModel.isLoading && feedViewModel.videos.isEmpty
        case .archive:
            return archiveViewModel.isLoading && archiveViewModel.selectedCollection?.videos.isEmpty == true
        case .search:
            return isSearching
        case .grid:
            return false
        }
    }
    
    private var emptyStateMessage: String {
        switch mode {
        case .feed:
            return "No videos available"
        case .archive:
            return "Select a collection to view videos"
        case .search:
            return searchQuery.isEmpty ? "Enter a search term" : "No videos found"
        case .grid:
            return "No videos available"
        }
    }
    
    private var shouldShowNavigation: Bool {
        mode != .search && mode != .grid
    }
    
    private func handleVideoChange(_ newValue: Int) async {
        switch mode {
        case .feed:
            if newValue >= feedViewModel.videos.count - 2 {
                await feedViewModel.loadMoreVideos()
            }
        case .archive:
            if let collection = archiveViewModel.selectedCollection {
                await archiveViewModel.loadMoreVideosIfNeeded(for: collection, currentIndex: newValue)
            }
        case .search:
            // Search results are loaded all at once, no pagination needed
            break
        case .grid:
            // Grid mode doesn't need pagination
            break
        }
    }
    
    private func handleInitialLoad() async {
        switch mode {
        case .feed:
            if feedViewModel.videos.isEmpty {
                await feedViewModel.loadInitialVideos()
            }
        case .archive:
            // Collection videos are loaded when a collection is selected
            break
        case .search:
            if !searchQuery.isEmpty {
                if searchQuery.hasPrefix("#") {
                    await feedViewModel.searchVideos(hashtag: String(searchQuery.dropFirst()))
                } else {
                    await feedViewModel.searchByText(searchQuery)
                }
            }
        case .grid:
            // Grid mode doesn't need initial load
            break
        }
    }
    
    private func prefetchUpcomingVideos(currentIndex: Int) async {
        guard !isPrefetching else { return }
        isPrefetching = true
        defer { isPrefetching = false }
        
        // Wait for current video to be ready before prefetching next ones
        try? await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
        
        let nextIndices = [currentIndex + 1, currentIndex + 2]
        
        for nextIndex in nextIndices {
            guard nextIndex < currentVideos.count else {
                print("UnifiedVideoView: No more videos to prefetch")
                return
            }
            
            let video = currentVideos[nextIndex]
            if let url = URL(string: video.videoURL) {
                print("UnifiedVideoView: Prefetching video at index \(nextIndex)")
                
                do {
                    // Add increasing delay for each subsequent video
                    if nextIndex > currentIndex + 1 {
                        try await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 second delay
                    }
                    await VideoAssetLoader.shared.prefetchWithPriority(for: url, priority: nextIndex == currentIndex + 1 ? .high : .low)
                } catch {
                    print("UnifiedVideoView: Prefetch cancelled for index \(nextIndex)")
                }
            }
        }
    }
    
    private func cleanupDistantVideos(currentIndex: Int) {
        // Only keep current video and immediate neighbors
        let bufferSize = 1  // Keep only 1 video on each side
        let lowerBound = max(0, currentIndex - bufferSize)
        let upperBound = min(currentIndex + bufferSize, currentVideos.count - 1)
        
        guard lowerBound <= upperBound else {
            print("UnifiedVideoView: Invalid range for cleanup, skipping")
            return
        }
        
        let keepRange = lowerBound...upperBound
        print("UnifiedVideoView: Keeping videos in range \(keepRange)")
        
        // Cleanup videos outside our buffer range
        for (index, video) in currentVideos.enumerated() {
            if !keepRange.contains(index) {
                if let url = URL(string: video.videoURL) {
                    print("UnifiedVideoView: Cleaning up video at index \(index)")
                    // Add slight delay to prevent cleanup during transitions
                    Task {
                        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 second delay
                        await VideoAssetLoader.shared.cleanupAsset(for: url)
                    }
                }
            }
        }
    }

    private func handleModeChange(_ newMode: ViewMode) {
        logger.debug("Mode changing from \(mode) to \(newMode)")
        mode = newMode
        
        // Reset search state when switching modes
        if mode != .search {
            logger.debug("Clearing search state due to mode change")
            searchQuery = ""
            feedViewModel.clearSearch()
        }
    }
}

extension View {
    @ViewBuilder func `if`<Content: View>(_ condition: Bool, transform: (Self) -> Content) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
