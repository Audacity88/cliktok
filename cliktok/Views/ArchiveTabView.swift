import SwiftUI
import AVKit
import Foundation

struct ArchiveTabView: View {
    @StateObject private var viewModel = ArchiveVideoViewModel()
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @State private var currentIndex = 0
    @State private var showCollections = false
    
    var body: some View {
        ZStack(alignment: .topTrailing) {
            GeometryReader { geometry in
                ZStack {
                    Color.black.edgesIgnoringSafeArea(.all)
                    
                    if viewModel.isLoading {
                        LoadingView()
                    } else if let selectedCollection = viewModel.selectedCollection,
                              !selectedCollection.videos.isEmpty {
                        TabView(selection: $currentIndex) {
                            ForEach(Array(selectedCollection.videos.enumerated()), id: \.element.id) { index, archiveVideo in
                                VideoPlayerView(
                                    video: Video(
                                        userID: "archive",
                                        videoURL: archiveVideo.videoURL,
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
                                .onAppear {
                                    print("ArchiveTabView: Video \(index) appeared")
                                    prefetchUpcomingVideos(currentIndex: index, in: selectedCollection)
                                }
                                .onDisappear {
                                    print("ArchiveTabView: Video \(index) disappeared")
                                    cleanupDistantVideos(currentIndex: index, in: selectedCollection)
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
                        prefetchUpcomingVideos(currentIndex: newValue, in: collection)
                        cleanupDistantVideos(currentIndex: newValue, in: collection)
                    }
                }
                .task {
                    if let collection = viewModel.selectedCollection,
                       !collection.videos.isEmpty,
                       let firstVideoURL = URL(string: collection.videos[0].videoURL) {
                        print("ArchiveTabView: Prefetching first video immediately")
                        await VideoAssetLoader.shared.prefetchWithPriority(for: firstVideoURL, priority: .high)
                    }
                    if let collection = viewModel.selectedCollection {
                        prefetchUpcomingVideos(currentIndex: 0, in: collection)
                    }
                }
            }
            
            // Fixed position collections button
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
    
    private func prefetchUpcomingVideos(currentIndex: Int, in collection: ArchiveCollection) {
        // Prefetch next 2 videos
        for offset in 1...2 {
            let nextIndex = currentIndex + offset
            guard nextIndex < collection.videos.count else { continue }
            
            if let nextURL = URL(string: collection.videos[nextIndex].videoURL) {
                print("ArchiveTabView: Prefetching video at index \(nextIndex)")
                Task {
                    await VideoAssetLoader.shared.prefetchWithPriority(for: nextURL, priority: offset == 1 ? .high : .medium)
                }
            }
        }
    }
    
    private func cleanupDistantVideos(currentIndex: Int, in collection: ArchiveCollection) {
        // Cleanup videos that are more than 2 positions away
        for (index, video) in collection.videos.enumerated() {
            if abs(index - currentIndex) > 2 {
                if let url = URL(string: video.videoURL) {
                    print("ArchiveTabView: Cleaning up distant video at index \(index)")
                    VideoAssetLoader.shared.cleanupAsset(for: url)
                }
            }
        }
    }
}
