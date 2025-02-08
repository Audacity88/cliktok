import Foundation
import SwiftUI

@MainActor
class ArchiveVideoViewModel: ObservableObject {
    @Published var collections: [ArchiveCollection] = []
    @Published var selectedCollection: ArchiveCollection?
    @Published var isLoading = false
    @Published var error: String?
    
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
            (id: "animation_movies", title: "Animation Movies", description: "Classic animated films from the public domain")
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
        
        // Initialize empty collection if needed
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            var updatedCollection = collection
            if updatedCollection.videos.isEmpty {
                updatedCollection.videos = []
                collections[index] = updatedCollection
                selectedCollection = updatedCollection
            }
        }
        
        // Load initial page
        await loadMoreVideos(for: collection, startIndex: 0)
        
        isLoading = false
    }
    
    func loadMoreVideosIfNeeded(for collection: ArchiveCollection, currentIndex: Int) async {
        guard !isLoadingMore,
              collection.id != "test_videos",
              currentIndex >= collection.videos.count - 2 // Load more when approaching end
        else { return }
        
        await loadMoreVideos(for: collection, startIndex: collection.videos.count)
    }
    
    private func loadMoreVideos(for collection: ArchiveCollection, startIndex: Int) async {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        // Check if range is already loaded
        let range = startIndex..<(startIndex + pageSize)
        if loadedRanges[collection.id]?.contains(where: { $0.overlaps(range) }) ?? false {
            return
        }
        
        do {
            let videos = try await api.fetchCollectionItems(
                identifier: collection.id,
                offset: startIndex,
                limit: pageSize
            )
            
            if !videos.isEmpty {
                if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                    var updatedCollection = collections[index]
                    
                    // Append new videos
                    if startIndex >= updatedCollection.videos.count {
                        updatedCollection.videos.append(contentsOf: videos)
                    } else {
                        // Insert videos at correct position
                        for (i, video) in videos.enumerated() {
                            let insertIndex = startIndex + i
                            if insertIndex < updatedCollection.videos.count {
                                updatedCollection.videos[insertIndex] = video
                            } else {
                                updatedCollection.videos.append(video)
                            }
                        }
                    }
                    
                    collections[index] = updatedCollection
                    if selectedCollection?.id == collection.id {
                        selectedCollection = updatedCollection
                    }
                    
                    // Mark range as loaded
                    var ranges = loadedRanges[collection.id] ?? Set<Range<Int>>()
                    ranges.insert(range)
                    loadedRanges[collection.id] = ranges
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
