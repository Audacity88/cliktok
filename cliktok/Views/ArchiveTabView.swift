import SwiftUI
import AVKit
import Foundation

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
        // Try to get mp4 version for m4v files
        if url.hasSuffix(".m4v") {
            let mp4URL = url.replacingOccurrences(of: ".m4v", with: ".mp4")
            print("ArchiveTabView: Attempting to use MP4 version: \(mp4URL)")
            return mp4URL
        }
        
        // For other formats, keep original URL
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
                                VideoPlayerView(
                                    video: Video(
                                        userID: "archive",
                                        videoURL: getOptimizedVideoURL(archiveVideo.videoURL),
                                        caption: archiveVideo.title,
                                        hashtags: ["archive"]
                                    ),
                                    showBackButton: false,
                                    clearSearchOnDismiss: .constant(false),
                                    isVisible: .constant(index == currentIndex)
                                )
                                .environmentObject(feedViewModel)
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
                                .foregroundColor(.white)
                            Button("Select Collection") {
                                showCollections = true
                            }
                            .buttonStyle(.bordered)
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
            Button {
                showCollections = true
            } label: {
                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 30))
                    .foregroundColor(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.black.opacity(0.5))
                    .clipShape(Circle())
            }
            .padding(.top, 50)
            .padding(.trailing, 24)
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
