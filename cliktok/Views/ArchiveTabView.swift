import SwiftUI
import AVKit
import Foundation

private extension String {
    func optimizedVideoURL() -> String {
        if self.hasSuffix(".m4v") {
            let mp4URL = self.replacingOccurrences(of: ".m4v", with: ".mp4")
            print("ArchiveTabView: Attempting to use MP4 version: \(mp4URL)")
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

struct RetroProgressBar: View {
    let progress: Double
    
    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 4)
                
                Rectangle()
                    .fill(Color.green)
                    .frame(width: geometry.size.width * progress, height: 4)
            }
        }
        .frame(height: 4)
    }
}

struct RetroControlButton: View {
    let systemName: String
    let action: () -> Void
    var isActive: Bool = false
    
    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24))
                .foregroundColor(isActive ? .green : .white)
                .frame(width: 44, height: 44)
                .background(Color.black.opacity(0.5))
                .clipShape(Circle())
        }
    }
}

struct ArchiveVideoPlayerContent: View {
    let archiveVideo: ArchiveVideo
    let index: Int
    let currentIndex: Int
    let archiveUserID: String
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    
    var body: some View {
        VideoPlayerView(
            video: Video(
                id: archiveVideo.id,
                userID: archiveUserID,
                videoURL: archiveVideo.videoURL.optimizedVideoURL(),
                caption: archiveVideo.title,
                description: archiveVideo.description,
                hashtags: ["archive"],
                createdAt: Date(),
                likes: 0,
                views: 0
            ),
            showBackButton: false,
            clearSearchOnDismiss: .constant(false),
            isVisible: .constant(index == currentIndex),
            showCreator: false
        )
        .environmentObject(feedViewModel)
    }
}

struct ArchiveVideoList: View {
    let collection: ArchiveCollection
    let currentIndex: Int
    let geometry: GeometryProxy
    let archiveUserID: String
    let viewModel: ArchiveVideoViewModel
    @Binding var selectedIndex: Int
    
    var body: some View {
        TabView(selection: $selectedIndex) {
            ForEach(Array(collection.videos.enumerated()), id: \.element.id) { index, archiveVideo in
                ZStack {
                    ArchiveVideoPlayerContent(
                        archiveVideo: archiveVideo,
                        index: index,
                        currentIndex: selectedIndex,
                        archiveUserID: archiveUserID
                    )
                }
                .frame(width: geometry.size.width, height: geometry.size.height)
                .rotationEffect(.degrees(-90))
                .tag(index)
                .task(id: index) {
                    guard index == selectedIndex else { return }
                    print("ArchiveTabView: Video \(index) appeared")
                    
                    if index >= collection.videos.count - 2 {
                        print("ArchiveTabView: Approaching end, loading more videos...")
                        await viewModel.loadMoreVideosIfNeeded(for: collection, currentIndex: index)
                    }
                }
                .overlay(alignment: .bottom) {
                    if viewModel.isLoading && index >= collection.videos.count - 2 {
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

struct ArchiveTabView: View {
    @StateObject private var viewModel: ArchiveVideoViewModel
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @State private var currentIndex = 0
    @State private var showCollections = false
    @State private var isPrefetching = false
    @State private var visibleRange: Range<Int> = 0..<3
    
    // Archive user ID for tipping
    private let archiveUserID = "archive_user"
    
    init() {
        _viewModel = StateObject(wrappedValue: ArchiveVideoViewModel())
    }
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    if viewModel.isLoading && viewModel.selectedCollection?.videos.isEmpty == true {
                        LoadingView()
                    } else if let selectedCollection = viewModel.selectedCollection,
                              !selectedCollection.videos.isEmpty {
                        ArchiveVideoList(
                            collection: selectedCollection,
                            currentIndex: currentIndex,
                            geometry: geometry,
                            archiveUserID: archiveUserID,
                            viewModel: viewModel,
                            selectedIndex: $currentIndex
                        )
                    } else {
                        VStack {
                            Text("No videos available")
                                .font(.system(.body, design: .monospaced))
                                .foregroundColor(.green)
                            Button("Select Collection") {
                                showCollections = true
                            }
                            .buttonStyle(.bordered)
                            .tint(.green)
                        }
                    }
                }
                .onChange(of: currentIndex) { oldValue, newValue in
                    print("ArchiveTabView: Switched from video \(oldValue) to \(newValue)")
                    if let collection = viewModel.selectedCollection {
                        Task {
                            if newValue >= collection.videos.count - 2 {
                                print("ArchiveTabView: Approaching end, loading more videos...")
                                await viewModel.loadMoreVideosIfNeeded(for: collection, currentIndex: newValue)
                            }
                            
                            await prefetchUpcomingVideos(currentIndex: newValue, in: collection)
                            cleanupDistantVideos(currentIndex: newValue, in: collection)
                        }
                    }
                }
                .task(id: viewModel.selectedCollection?.id) {
                    if let collection = viewModel.selectedCollection,
                       !collection.videos.isEmpty {
                        if let firstVideoURL = URL(string: collection.videos[0].videoURL) {
                            print("ArchiveTabView: Aggressively preloading first video")
                            await VideoAssetLoader.shared.prefetchWithPriority(for: firstVideoURL, priority: .high)
                        }
                        visibleRange = 0..<min(3, collection.videos.count)
                    }
                }
            }
            
            // Collections button
            RetroControlButton(systemName: "square.grid.2x2", action: {
                showCollections = true
            }, isActive: true)
            .padding(.top, 50)
            .padding(.trailing, 16)
        }
        .sheet(isPresented: $showCollections) {
            ArchiveCollectionGalleryView(selectedCollection: $viewModel.selectedCollection)
                .environmentObject(viewModel)
        }
    }
    
    private func prefetchUpcomingVideos(currentIndex: Int, in collection: ArchiveCollection) async {
        guard !isPrefetching else { return }
        isPrefetching = true
        defer { isPrefetching = false }
        
        // Prefetch the next two videos to ensure smooth playback
        let nextIndices = [currentIndex + 1, currentIndex + 2]
        
        for nextIndex in nextIndices {
            guard nextIndex < collection.videos.count else {
                print("ArchiveTabView: No more videos to prefetch")
                return
            }
            
            let videoURL = collection.videos[nextIndex].videoURL.optimizedVideoURL()
            if let url = URL(string: videoURL) {
                print("ArchiveTabView: Prefetching video at index \(nextIndex)")
                
                do {
                    // Add a small delay between prefetches to reduce load
                    if nextIndex > currentIndex + 1 {
                        try await Task.sleep(nanoseconds: 500_000_000) // 0.5 second delay
                    }
                    await VideoAssetLoader.shared.prefetchWithPriority(for: url, priority: nextIndex == currentIndex + 1 ? .high : .medium)
                } catch {
                    print("ArchiveTabView: Prefetch cancelled for index \(nextIndex)")
                }
            }
        }
    }
    
    private func cleanupDistantVideos(currentIndex: Int, in collection: ArchiveCollection) {
        // Keep a buffer of videos before and after the current index
        let bufferSize = 2
        let lowerBound = max(0, currentIndex - bufferSize)
        let upperBound = min(currentIndex + bufferSize, collection.videos.count - 1)
        
        // Only proceed if we have valid bounds
        guard lowerBound <= upperBound else {
            print("ArchiveTabView: Invalid range for cleanup, skipping")
            return
        }
        
        let keepRange = lowerBound...upperBound
        print("ArchiveTabView: Keeping videos in range \(keepRange)")
        
        // Cleanup videos outside the keep range
        for (index, video) in collection.videos.enumerated() {
            if !keepRange.contains(index) {
                if let url = URL(string: video.videoURL.optimizedVideoURL()) {
                    print("ArchiveTabView: Cleaning up video at index \(index)")
                    VideoAssetLoader.shared.cleanupAsset(for: url)
                }
            }
        }
    }
}
