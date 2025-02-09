import SwiftUI
import AVKit
import Foundation

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

struct ArchiveTabView: View {
    @StateObject private var viewModel: ArchiveVideoViewModel
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @State private var currentIndex = 0
    @State private var showCollections = false
    @State private var isPrefetching = false
    @State private var visibleRange: Range<Int> = 0..<3
    
    init() {
        _viewModel = StateObject(wrappedValue: ArchiveVideoViewModel())
    }
    
    private func getOptimizedVideoURL(_ url: String) -> String {
        if url.hasSuffix(".m4v") {
            let mp4URL = url.replacingOccurrences(of: ".m4v", with: ".mp4")
            print("ArchiveTabView: Attempting to use MP4 version: \(mp4URL)")
            return mp4URL
        }
        return url
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
                        TabView(selection: $currentIndex) {
                            ForEach(Array(selectedCollection.videos.enumerated()), id: \.element.id) { index, archiveVideo in
                                ZStack {
                                    VideoPlayerView(
                                        video: Video(
                                            userID: "archive",
                                            videoURL: getOptimizedVideoURL(archiveVideo.videoURL),
                                            caption: archiveVideo.title,
                                            description: archiveVideo.description,
                                            hashtags: ["archive"]
                                        ),
                                        showBackButton: false,
                                        clearSearchOnDismiss: .constant(false),
                                        isVisible: .constant(index == currentIndex)
                                    )
                                    .environmentObject(feedViewModel)
                                }
                                .frame(width: geometry.size.width, height: geometry.size.height)
                                .rotationEffect(.degrees(-90))
                                .tag(index)
                                .task(id: index) {
                                    guard index == currentIndex else { return }
                                    print("ArchiveTabView: Video \(index) appeared")
                                    
                                    // Load more videos when we're 2 videos away from the end
                                    if index >= selectedCollection.videos.count - 2 {
                                        print("ArchiveTabView: Approaching end, loading more videos...")
                                        await viewModel.loadMoreVideosIfNeeded(for: selectedCollection, currentIndex: index)
                                    }
                                    
                                    if let collection = viewModel.selectedCollection {
                                        await prefetchUpcomingVideos(currentIndex: index, in: collection)
                                    }
                                }
                                .onDisappear {
                                    print("ArchiveTabView: Video \(index) disappeared")
                                    if let collection = viewModel.selectedCollection {
                                        cleanupDistantVideos(currentIndex: index, in: collection)
                                    }
                                }
                                .overlay(alignment: .bottom) {
                                    if viewModel.isLoading && index >= selectedCollection.videos.count - 2 {
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
                            // Load more videos when we're 2 videos away from the end
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
                        // Only preload the first video initially
                        if let firstVideoURL = URL(string: getOptimizedVideoURL(collection.videos[0].videoURL)) {
                            print("ArchiveTabView: Aggressively preloading first video")
                            await VideoAssetLoader.shared.prefetchWithPriority(for: firstVideoURL, priority: .high)
                        }
                        
                        // Set initial visible range
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
        
        // Only prefetch the next video to reduce errors and memory pressure
        let nextIndex = currentIndex + 1
        guard nextIndex < collection.videos.count else {
            print("ArchiveTabView: No more videos to prefetch")
            return
        }
        
        let videoURL = collection.videos[nextIndex].videoURL
        if let url = URL(string: getOptimizedVideoURL(videoURL)) {
            print("ArchiveTabView: Prefetching next video at index \(nextIndex)")
            
            do {
                // Wait for current video to start playing
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                await VideoAssetLoader.shared.prefetchWithPriority(for: url, priority: .high)
            } catch {
                print("ArchiveTabView: Prefetch cancelled for index \(nextIndex)")
            }
        }
    }
    
    private func cleanupDistantVideos(currentIndex: Int, in collection: ArchiveCollection) {
        // Calculate the upper bound safely
        let upperBound = min(currentIndex + 1, collection.videos.count - 1)
        
        // Only proceed if we have valid bounds
        guard currentIndex <= upperBound else {
            print("ArchiveTabView: Invalid range for cleanup, skipping")
            return
        }
        
        let keepRange = currentIndex...upperBound
        
        // Cleanup videos outside the keep range
        for (index, video) in collection.videos.enumerated() {
            if !keepRange.contains(index) {
                if let url = URL(string: video.videoURL) {
                    print("ArchiveTabView: Cleaning up video at index \(index)")
                    VideoAssetLoader.shared.cleanupAsset(for: url)
                }
            }
        }
    }
}
