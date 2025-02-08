import Foundation
import SwiftUI

@MainActor
class ArchiveVideoViewModel: ObservableObject {
    @Published var collections: [ArchiveCollection] = []
    @Published var selectedCollection: ArchiveCollection?
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMoreVideos = true
    
    private let api = InternetArchiveAPI.shared
    private var loadedRanges: [String: Set<Range<Int>>] = [:]
    private let pageSize = 5
    private var isLoadingMore = false
    
    init() {
        // Add initial collections
        addTestCollections()
    }
    
    private func addTestCollections() {
        // Test Videos Collection
        let testVideos = ArchiveCollection(
            id: "test_videos",
            title: "Test Videos",
            description: "Sample videos for testing",
            videos: [
                ArchiveVideo(
                    title: "Test Pattern",
                    videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                    description: "Test video for streaming"
                ),
                ArchiveVideo(
                    title: "Big Buck Bunny",
                    videoURL: "https://archive.org/download/BigBuckBunny_328/BigBuckBunny_512kb.mp4",
                    description: "Big Buck Bunny - Classic open source animation"
                ),
                ArchiveVideo(
                    title: "Elephants Dream",
                    videoURL: "https://archive.org/download/ElephantsDream/ed_1024_512kb.mp4",
                    description: "Elephants Dream - First Blender Open Movie"
                )
            ]
        )
        
        // Add Internet Archive Collections
        let archiveCollections = [
            (id: "demolitionkitchenvideo", title: "Demolition Kitchen", description: "Videos from the Demolition Kitchen collection"),
            (id: "prelinger", title: "Prelinger Archives", description: "Historical films from the Prelinger Archives"),
            (id: "artsandmusicvideos", title: "Arts & Music", description: "A collection of arts and music videos from the Internet Archive")
        ]
        
        let archiveCollectionModels = archiveCollections.map { collection in
            ArchiveCollection(
                id: collection.id,
                title: collection.title,
                description: collection.description,
                thumbnailURL: InternetArchiveAPI.getThumbnailURL(identifier: collection.id).absoluteString
            )
        }
        
        collections = [testVideos] + archiveCollectionModels
        selectedCollection = testVideos
    }
    
    func loadCollectionVideos(for collection: ArchiveCollection) async {
        guard collection.id != "test_videos" else { return }
        
        isLoading = true
        error = nil
        hasMoreVideos = true  // Reset this flag when loading a new collection
        
        // Clear any existing videos for this collection
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            var updatedCollection = collection
            updatedCollection.videos = []
            collections[index] = updatedCollection
            selectedCollection = updatedCollection
        }
        
        // Load initial page
        await loadMoreVideos(for: collection, startIndex: 0)
        
        isLoading = false
    }
    
    func loadMoreVideosIfNeeded(for collection: ArchiveCollection, currentIndex: Int) async {
        guard !isLoadingMore,
              collection.id != "test_videos",
              hasMoreVideos,  // Check if we have more videos to load
              currentIndex >= collection.videos.count - 2 // Load more when approaching end
        else {
            print("ArchiveVideoViewModel: Skipping load - isLoadingMore: \(!isLoadingMore), isTestVideos: \(collection.id == "test_videos"), hasMoreVideos: \(hasMoreVideos), currentIndex: \(currentIndex), total videos: \(collection.videos.count)")
            return
        }
        
        print("ArchiveVideoViewModel: Loading more videos starting at index \(collection.videos.count)")
        isLoading = true
        defer { isLoading = false }
        
        await loadMoreVideos(for: collection, startIndex: collection.videos.count)
    }
    
    private func loadMoreVideos(for collection: ArchiveCollection, startIndex: Int) async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        // Check if range is already loaded
        let range = startIndex..<(startIndex + pageSize)
        if loadedRanges[collection.id]?.contains(where: { $0.overlaps(range) }) ?? false {
            print("ArchiveVideoViewModel: Range \(range) already loaded")
            return
        }
        
        do {
            print("ArchiveVideoViewModel: Fetching videos from \(startIndex) to \(startIndex + pageSize)")
            let videos = try await api.fetchCollectionItems(
                identifier: collection.id,
                offset: startIndex,
                limit: pageSize
            )
            
            if videos.isEmpty {
                print("ArchiveVideoViewModel: No more videos available")
                hasMoreVideos = false
                return
            }
            
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                var updatedCollection = collections[index]
                
                // Always append new videos at the end
                updatedCollection.videos.append(contentsOf: videos)
                
                collections[index] = updatedCollection
                if selectedCollection?.id == collection.id {
                    selectedCollection = updatedCollection
                }
                
                // Mark range as loaded
                var ranges = loadedRanges[collection.id] ?? Set<Range<Int>>()
                ranges.insert(range)
                loadedRanges[collection.id] = ranges
                
                print("ArchiveVideoViewModel: Added \(videos.count) more videos. Total count: \(updatedCollection.videos.count)")
            }
        } catch {
            self.error = error.localizedDescription
            hasMoreVideos = false  // Set this to false on error to prevent endless retries
            print("ArchiveVideoViewModel: Error loading more videos: \(error.localizedDescription)")
        }
    }
}
