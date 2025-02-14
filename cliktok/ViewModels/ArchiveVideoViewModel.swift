import Foundation
import SwiftUI
import FirebaseFirestore
import FirebaseAuth

@MainActor
class ArchiveVideoViewModel: ObservableObject {
    @Published var collections: [ArchiveCollection] = []
    @Published var selectedCollection: ArchiveCollection?
    @Published var isLoading = false
    @Published var error: String?
    @Published var hasMoreVideos = true
    
    private let api = InternetArchiveAPI.shared
    private var loadedRanges: [String: Set<Range<Int>>] = [:]
    private let pageSize = 10
    private var isLoadingMore = false
    private var prefetchTasks: [String: Task<Void, Never>] = [:]
    private var lastLoadDirection: LoadDirection = .forward
    private var videoCache: [String: [ArchiveVideo]] = [:]
    private var preloadTask: Task<Void, Never>?
    private var activeTasks: Set<Task<Void, Never>> = []
    
    enum LoadDirection {
        case forward
        case backward
    }
    
    init() {
        addInitialCollections()
    }
    
    private func addInitialCollections() {
        // Add Internet Archive Collections
        let archiveCollections = [
            (id: "demolitionkitchenvideo", title: "Demolition Kitchen", description: "Videos from the Demolition Kitchen collection"),
            (id: "prelinger", title: "Prelinger Archives", description: "Historical films from the Prelinger Archives"),
            (id: "artsandmusicvideos", title: "Arts & Music", description: "A collection of arts and music videos from the Internet Archive"),
            (id: "classic_tv", title: "Classic TV", description: "Classic television shows and commercials"),
            (id: "opensource_movies", title: "Open Source Movies", description: "Community contributed open source films"),
            (id: "sports", title: "Sports Archive", description: "Historical sports footage and memorable sporting moments"),
            (id: "movie_trailers", title: "Movie Trailers", description: "Collection of classic and contemporary movie trailers"),
            (id: "newsandpublicaffairs", title: "News & Public Affairs", description: "Historical news footage and public affairs programming")
        ]
        
        let archiveCollectionModels = archiveCollections.map { collection in
            ArchiveCollection(
                id: collection.id,
                title: collection.title,
                description: collection.description,
                thumbnailURL: InternetArchiveAPI.getThumbnailURL(identifier: collection.id).absoluteString
            )
        }
        
        collections = archiveCollectionModels
        selectedCollection = archiveCollectionModels.first
    }
    
    private func prefetchCollections(_ collections: [ArchiveCollection]) async {
        // Only prefetch first 2 collections to reduce load
        for collection in collections.prefix(2) {
            // Don't prefetch test videos
            guard collection.id != "test_videos" else { continue }
            
            // Cancel any existing prefetch task for this collection
            prefetchTasks[collection.id]?.cancel()
            
            // Add increasing delay for each collection to prevent overwhelming the API
            if let index = collections.firstIndex(of: collection), index > 0 {
                try? await Task.sleep(nanoseconds: UInt64(index) * 2_000_000_000) // 2 second delay per collection
            }
            
            let task = Task {
                do {
                    // Only fetch first 3 videos per collection for prefetch
                    let videos = try await api.fetchCollectionItems(
                        identifier: collection.id,
                        offset: 0,
                        limit: 3
                    )
                    
                    // Cache the videos metadata only if task wasn't cancelled
                    if !Task.isCancelled {
                        await MainActor.run {
                            if let index = self.collections.firstIndex(where: { $0.id == collection.id }) {
                                var updatedCollection = self.collections[index]
                                updatedCollection.videos = videos
                                self.collections[index] = updatedCollection
                                
                                // Mark range as loaded
                                var ranges = self.loadedRanges[collection.id] ?? Set<Range<Int>>()
                                ranges.insert(0..<3)
                                self.loadedRanges[collection.id] = ranges
                            }
                        }
                        
                        // Only prefetch thumbnails for first video
                        if let firstVideo = videos.first,
                           let thumbnailURL = URL(string: InternetArchiveAPI.getThumbnailURL(identifier: firstVideo.id).absoluteString) {
                            await ImageCache.shared.prefetchImages([thumbnailURL])
                        }
                    }
                } catch {
                    print("Error prefetching collection \(collection.id): \(error)")
                }
            }
            
            prefetchTasks[collection.id] = task
        }
    }
    
    func loadCollectionVideos(for collection: ArchiveCollection) async {
        guard collection.id != "test_videos" else { return }
        
        isLoading = true
        error = nil
        hasMoreVideos = true
        
        // Clear all caches when switching collections
        clearCaches()
        
        // If we already have videos for this collection, use them
        if let existingCollection = collections.first(where: { $0.id == collection.id }),
           !existingCollection.videos.isEmpty {
            selectedCollection = existingCollection
            isLoading = false
            return
        }
        
        // Clear loaded ranges for this collection
        loadedRanges[collection.id] = Set<Range<Int>>()
        
        // Clear any existing videos for this collection
        if let index = collections.firstIndex(where: { $0.id == collection.id }) {
            var updatedCollection = collection
            updatedCollection.videos = []
            collections[index] = updatedCollection
            selectedCollection = updatedCollection
        }
        
        // Cancel any existing prefetch task
        prefetchTasks[collection.id]?.cancel()
        
        do {
            // Load initial page
            try await loadMoreVideos(for: collection, startIndex: 0)
            
            // Prefetch other collections when a collection is selected
            let otherCollections = collections.filter { $0.id != collection.id && $0.id != "test_videos" }
            await prefetchCollections(otherCollections)
        } catch {
            self.error = "Failed to load videos: \(error.localizedDescription)"
            print("Error loading collection: \(error)")
        }
        
        isLoading = false
    }
    
    private func clearCaches() {
        // Clear view model caches
        videoCache.removeAll()
        loadedRanges.removeAll()
        prefetchTasks.forEach { $0.value.cancel() }
        prefetchTasks.removeAll()
        
        // Clear API caches
        Task {
            await api.clearCaches()
        }
    }
    
    private func loadMoreVideos(for collection: ArchiveCollection, startIndex: Int) async throws {
        guard !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        
        // Determine load direction
        let currentDirection: LoadDirection = startIndex >= (collection.videos.count - pageSize) ? .forward : .backward
        lastLoadDirection = currentDirection
        
        // Calculate ranges to load
        let primaryRange = startIndex..<(startIndex + pageSize)
        let prefetchRange = currentDirection == .forward ? 
            (startIndex + pageSize)..<(startIndex + (pageSize * 2)) :
            (startIndex - pageSize)..<startIndex
        
        // Load primary and prefetch ranges in parallel
        do {
            let videos = try await api.fetchCollectionItems(
                identifier: collection.id,
                offset: primaryRange.lowerBound,
                limit: pageSize
            )
            
            if videos.isEmpty {
                hasMoreVideos = false
                return
            }
            
            // Update collection with loaded videos
            await updateCollectionVideos(collection, videos: videos, range: primaryRange)
            
            // Prefetch next page if available
            if hasMoreVideos && prefetchRange.lowerBound >= 0 {
                Task {
                    do {
                        let prefetchedVideos = try await api.fetchCollectionItems(
                            identifier: collection.id,
                            offset: prefetchRange.lowerBound,
                            limit: pageSize
                        )
                        if !prefetchedVideos.isEmpty {
                            await updateCollectionVideos(collection, videos: prefetchedVideos, range: prefetchRange)
                        }
                    } catch {
                        print("Error prefetching next page: \(error)")
                    }
                }
            }
        } catch {
            throw error
        }
    }
    
    private func updateCollectionVideos(_ collection: ArchiveCollection, videos: [ArchiveVideo], range: Range<Int>) async {
        await MainActor.run { [weak self] in
            guard let self = self else { return }
            guard let index = collections.firstIndex(where: { $0.id == collection.id }) else { return }
            
            var updatedCollection = collections[index]
            
            // Ensure the videos array is large enough
            while updatedCollection.videos.count < range.upperBound {
                updatedCollection.videos.append(contentsOf: Array(repeating: ArchiveVideo(
                    id: UUID().uuidString,
                    title: "",
                    videoURL: "",
                    thumbnailURL: nil,
                    description: nil
                ), count: range.upperBound - updatedCollection.videos.count))
            }
            
            // Update videos at the correct indices
            for (offset, video) in videos.enumerated() {
                let targetIndex = range.lowerBound + offset
                if targetIndex < updatedCollection.videos.count {
                    updatedCollection.videos[targetIndex] = video
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
    
    private func prefetchAssetsForVideos(_ videos: ArraySlice<ArchiveVideo>) async {
        let task = Task { [weak self] in
            await withTaskGroup(of: Void.self) { group in
                for video in videos {
                    guard !Task.isCancelled else { break }
                    
                    group.addTask { [weak self] in
                        guard self != nil else { return }
                        if let url = URL(string: video.videoURL) {
                            await VideoAssetLoader.shared.prefetchWithPriority(for: url, priority: .low)
                        }
                    }
                    
                    if let thumbnailURL = URL(string: InternetArchiveAPI.getThumbnailURL(identifier: video.id).absoluteString) {
                        group.addTask { [weak self] in
                            guard self != nil else { return }
                            await ImageCache.shared.prefetchImages([thumbnailURL])
                        }
                    }
                }
            }
        }
        activeTasks.insert(task)
    }
    
    func loadMoreVideosIfNeeded(for collection: ArchiveCollection, currentIndex: Int) async {
        guard !isLoadingMore,
              collection.id != "test_videos",
              hasMoreVideos
        else { return }
        
        let threshold = 2
        let isNearEnd = currentIndex >= collection.videos.count - threshold
        let isNearStart = currentIndex <= threshold
        
        if isNearEnd || isNearStart {
            let startIndex = isNearEnd ? collection.videos.count : max(0, currentIndex - pageSize)
            isLoading = true
            defer { isLoading = false }
            
            do {
                try await loadMoreVideos(for: collection, startIndex: startIndex)
            } catch {
                self.error = "Failed to load more videos: \(error.localizedDescription)"
                print("Error loading more videos: \(error)")
            }
        }
    }
    
    func preloadCollections() {
        guard preloadTask == nil else { return }
        
        preloadTask = Task { [weak self] in
            guard let self = self else { return }
            
            for collection in collections where collection.id != "test_videos" {
                guard !Task.isCancelled else { break }
                
                do {
                    let videos = try await api.fetchCollectionItems(
                        identifier: collection.id,
                        offset: 0,
                        limit: 1
                    )
                    
                    guard !Task.isCancelled else { break }
                    
                    if let index = self.collections.firstIndex(where: { $0.id == collection.id }) {
                        await MainActor.run { [weak self] in
                            guard let self = self else { return }
                            var updatedCollection = self.collections[index]
                            updatedCollection.videos = videos
                            self.collections[index] = updatedCollection
                            
                            // Mark range as loaded
                            var ranges = self.loadedRanges[collection.id] ?? Set<Range<Int>>()
                            ranges.insert(0..<1)
                            self.loadedRanges[collection.id] = ranges
                        }
                        
                        // Preload video thumbnail with low priority
                        if let videoThumbnailURL = URL(string: videos.first?.thumbnailURL ?? "") {
                            let thumbnailTask = Task.detached(priority: .background) {
                                await ImageCache.shared.prefetchImages([videoThumbnailURL])
                            }
                            activeTasks.insert(thumbnailTask)
                        }
                    }
                } catch {
                    print("Error preloading collection \(collection.id): \(error)")
                }
            }
        }
    }
    
    // Make this nonisolated so it can be called from deinit
    nonisolated func cancelPreloading() {
        Task { @MainActor [weak self] in
            await self?.cleanup()
        }
    }
    
    deinit {
        // Cancel tasks immediately in deinit
        Task { @MainActor [weak self] in
            await self?.cleanup()
        }
    }
    
    // Make cleanup nonisolated and handle actor-isolated operations properly
    nonisolated private func cleanup() async {
        await MainActor.run { [self] in
            // Cancel all active tasks
            activeTasks.forEach { $0.cancel() }
            activeTasks.removeAll()
            
            // Cancel all prefetch tasks
            prefetchTasks.values.forEach { $0.cancel() }
            prefetchTasks.removeAll()
            
            // Cancel preload task
            preloadTask?.cancel()
            preloadTask = nil
            
            // Clear caches
            videoCache.removeAll()
            loadedRanges.removeAll()
        }
        
        // Clear API caches (this is already actor-isolated)
        await api.clearCaches()
    }
}
