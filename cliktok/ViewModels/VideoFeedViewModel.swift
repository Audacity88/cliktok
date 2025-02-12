import Foundation
import FirebaseFirestore
import Combine

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var videoCreators: [String: User] = [:]
    @Published var searchResults: [Video] = []
    @Published var searchError: Error?
    @Published var hasMoreVideos = true
    
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 5
    private let db = Firestore.firestore()
    
    // Archive user for Internet Archive videos
    private let archiveUser = User(
        id: nil,  // Don't set the ID directly
        email: "archive@archive.org",
        username: "internetarchive",
        displayName: "Internet Archive",
        bio: "A digital library of Internet sites and other cultural artifacts in digital form.",
        profileImageURL: nil,
        isPrivateAccount: false,
        balance: 0.0,
        userRole: .regular,
        companyName: "Internet Archive"
    )
    
    init() {
        // Add archive user to creators with the correct key
        videoCreators["archive_user"] = archiveUser
    }
    
    private func fetchVideoStats(for videos: [Video]) async {
        print("VideoFeedViewModel: -------- Starting Stats Fetch --------")
        print("VideoFeedViewModel: Total videos to fetch stats for: \(videos.count)")
        print("VideoFeedViewModel: Video IDs: \(videos.map { $0.stableId }.joined(separator: ", "))")
        
        // Group videos by type (archive vs regular)
        let archiveVideos = videos.filter { $0.isArchiveVideo }
        let regularVideos = videos.filter { !$0.isArchiveVideo }
        print("VideoFeedViewModel: Found \(archiveVideos.count) archive videos and \(regularVideos.count) regular videos")
        
        // Fetch archive video stats
        if !archiveVideos.isEmpty {
            let archiveIds = archiveVideos.map { $0.statsDocumentId }
            print("VideoFeedViewModel: Fetching archive stats for IDs: \(archiveIds.joined(separator: ", "))")
            
            do {
                let snapshot = try await db.collection("archive_video_stats")
                    .whereField(FieldPath.documentID(), in: archiveIds)
                    .getDocuments()
                
                print("VideoFeedViewModel: Retrieved \(snapshot.documents.count) archive stat documents")
                
                let stats = snapshot.documents.reduce(into: [String: [String: Any]]()) { dict, doc in
                    dict[doc.documentID] = doc.data()
                }
                print("VideoFeedViewModel: Parsed stats data: \(stats)")
                
                // Update archive video views in both arrays
                for video in archiveVideos {
                    print("VideoFeedViewModel: Processing archive video: \(video.stableId)")
                    if let videoStats = stats[video.statsDocumentId] {
                        let views = videoStats["views"] as? Int ?? 0
                        print("VideoFeedViewModel: Found stats for \(video.stableId) - views: \(views)")
                        
                        // Update in main videos array
                        if let index = self.videos.firstIndex(where: { $0.stableId == video.stableId }) {
                            print("VideoFeedViewModel: Updating main array at index \(index)")
                            self.videos[index].views = views
                        } else {
                            print("VideoFeedViewModel: Video not found in main array")
                        }
                        
                        // Update in search results array
                        if let index = self.searchResults.firstIndex(where: { $0.stableId == video.stableId }) {
                            print("VideoFeedViewModel: Updating search results at index \(index)")
                            self.searchResults[index].views = views
                        } else {
                            print("VideoFeedViewModel: Video not found in search results")
                        }
                    } else {
                        print("VideoFeedViewModel: No stats found for archive video: \(video.stableId)")
                    }
                }
            } catch {
                print("VideoFeedViewModel: Error fetching archive stats: \(error)")
                print("VideoFeedViewModel: Full error details: \(error)")
            }
        }
        
        // Fetch regular video stats
        if !regularVideos.isEmpty {
            let regularIds = regularVideos.map { $0.statsDocumentId }
            print("VideoFeedViewModel: Fetching regular stats for IDs: \(regularIds.joined(separator: ", "))")
            
            do {
                let snapshot = try await db.collection("video_stats")
                    .whereField(FieldPath.documentID(), in: regularIds)
                    .getDocuments()
                
                print("VideoFeedViewModel: Retrieved \(snapshot.documents.count) regular stat documents")
                
                let stats = snapshot.documents.reduce(into: [String: [String: Any]]()) { dict, doc in
                    dict[doc.documentID] = doc.data()
                }
                print("VideoFeedViewModel: Parsed stats data: \(stats)")
                
                // Update regular video views in both arrays
                for video in regularVideos {
                    print("VideoFeedViewModel: Processing regular video: \(video.stableId)")
                    if let videoStats = stats[video.statsDocumentId] {
                        let views = videoStats["views"] as? Int ?? 0
                        print("VideoFeedViewModel: Found stats for \(video.stableId) - views: \(views)")
                        
                        // Update in main videos array
                        if let index = self.videos.firstIndex(where: { $0.stableId == video.stableId }) {
                            print("VideoFeedViewModel: Updating main array at index \(index)")
                            self.videos[index].views = views
                        } else {
                            print("VideoFeedViewModel: Video not found in main array")
                        }
                        
                        // Update in search results array
                        if let index = self.searchResults.firstIndex(where: { $0.stableId == video.stableId }) {
                            print("VideoFeedViewModel: Updating search results at index \(index)")
                            self.searchResults[index].views = views
                        } else {
                            print("VideoFeedViewModel: Video not found in search results")
                        }
                    } else {
                        print("VideoFeedViewModel: No stats found for regular video: \(video.stableId)")
                    }
                }
            } catch {
                print("VideoFeedViewModel: Error fetching regular stats: \(error)")
                print("VideoFeedViewModel: Full error details: \(error)")
            }
        }
        
        print("VideoFeedViewModel: -------- Stats Fetch Complete --------")
        print("VideoFeedViewModel: Final video array views: \(self.videos.map { "\($0.stableId): \($0.views)" }.joined(separator: ", "))")
        print("VideoFeedViewModel: Final search results views: \(self.searchResults.map { "\($0.stableId): \($0.views)" }.joined(separator: ", "))")
    }
    
    func loadInitialVideos() async {
        isLoading = true
        do {
            let snapshot = try await db.collection("videos")
                .order(by: "created_at", descending: true)
                .limit(to: pageSize)
                .getDocuments()
            
            videos = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
            
            lastDocument = snapshot.documents.last
            
            // Fetch creators and stats in parallel
            async let creatorsTask = fetchCreators(for: videos)
            async let statsTask = fetchVideoStats(for: videos)
            _ = await [try await creatorsTask, try await statsTask]
            
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    func loadMoreVideos() async {
        guard let last = lastDocument, !isLoading else { return }
        
        isLoading = true
        do {
            let snapshot = try await db.collection("videos")
                .order(by: "created_at", descending: true)
                .limit(to: pageSize)
                .start(afterDocument: last)
                .getDocuments()
            
            let newVideos = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
            
            videos.append(contentsOf: newVideos)
            lastDocument = snapshot.documents.last
            
            // Fetch creators and stats in parallel for new videos
            async let creatorsTask = fetchCreators(for: newVideos)
            async let statsTask = fetchVideoStats(for: newVideos)
            _ = await [try await creatorsTask, try await statsTask]
            
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    public func fetchCreators(for videos: [Video]) async {
        let creatorIds = Set(videos.map { $0.userID })
        print("Fetching creators for IDs: \(creatorIds)")
        
        for creatorId in creatorIds {
            if videoCreators[creatorId] == nil {
                do {
                    let docSnapshot = try await db.collection("users").document(creatorId).getDocument()
                    if docSnapshot.exists {
                        if let user = try? docSnapshot.data(as: User.self) {
                            print("Successfully loaded creator: \(user.displayName)")
                            videoCreators[creatorId] = user
                        }
                    } else {
                        print("No document found for creator ID: \(creatorId)")
                    }
                } catch {
                    print("Error fetching creator \(creatorId): \(error)")
                }
            }
        }
    }
    
    func getCreator(for video: Video) -> User? {
        return videoCreators[video.userID]
    }
    
    @MainActor
    func deleteVideo(_ video: Video) async throws {
        guard let videoId = video.id else { 
            throw NSError(domain: "VideoFeed", code: 400, userInfo: [NSLocalizedDescriptionKey: "Video ID not found"]) 
        }
        
        isLoading = true
        do {
            // Delete from Firestore
            try await db.collection("videos").document(videoId).delete()
            
            // Remove from local array
            if let index = videos.firstIndex(where: { $0.id == videoId }) {
                videos.remove(at: index)
            }
            isLoading = false
        } catch {
            isLoading = false
            throw error
        }
    }
    
    func updateVideoStats(video: Video) async throws {
        print("VideoFeedViewModel: Starting stats update for video: \(video.stableId)")
        print("VideoFeedViewModel: Video type: \(video.isArchiveVideo ? "Archive" : "Regular")")
        print("VideoFeedViewModel: Stats document ID: \(video.statsDocumentId)")
        
        let db = Firestore.firestore()
        let collectionName = video.isArchiveVideo ? "archive_video_stats" : "video_stats"
        let statsRef = db.collection(collectionName).document(video.statsDocumentId)
        
        print("VideoFeedViewModel: Using collection: \(collectionName)")
        
        do {
            // Try to get the document first
            print("VideoFeedViewModel: Fetching existing stats document")
            let docSnapshot = try await statsRef.getDocument()
            
            if docSnapshot.exists {
                print("VideoFeedViewModel: Existing stats document found, updating view count")
                // Document exists, update it
                try await statsRef.updateData([
                    "views": FieldValue.increment(Int64(1)),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                
                // Get the updated document to sync local state
                let updatedDoc = try await statsRef.getDocument()
                let updatedData = updatedDoc.data() ?? [:]
                let updatedViews = updatedData["views"] as? Int ?? 0
                
                // Update local video objects
                if let index = videos.firstIndex(where: { $0.stableId == video.stableId }) {
                    videos[index].views = updatedViews
                }
                if let index = searchResults.firstIndex(where: { $0.stableId == video.stableId }) {
                    searchResults[index].views = updatedViews
                }
                
                print("VideoFeedViewModel: Successfully updated stats for video: \(video.stableId)")
                print("VideoFeedViewModel: Current document data: \(updatedData)")
            } else {
                print("VideoFeedViewModel: No existing stats document found, creating new one")
                // Document doesn't exist, create it with initial stats
                try await statsRef.setData([
                    "views": 1,
                    "likes": 0,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
                
                // Update local video objects with initial view count of 1
                if let index = videos.firstIndex(where: { $0.stableId == video.stableId }) {
                    videos[index].views = 1
                }
                if let index = searchResults.firstIndex(where: { $0.stableId == video.stableId }) {
                    searchResults[index].views = 1
                }
                
                print("VideoFeedViewModel: Created initial stats document for video: \(video.stableId)")
            }
        } catch {
            print("VideoFeedViewModel: Error updating video stats: \(error.localizedDescription)")
            print("VideoFeedViewModel: Full error details: \(error)")
            throw error
        }
    }
    
    func searchVideos(hashtag: String) async {
        do {
            // Search in uploaded videos
            let uploadedSnapshot = try await db.collection("videos")
                .whereField("hashtags", arrayContains: hashtag.lowercased())
                .limit(to: 25)
                .getDocuments()
            
            let uploadedVideos = uploadedSnapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
            
            // Search in archive videos
            let archiveResults = await searchArchiveVideos(query: hashtag)
            
            // Combine results
            searchResults = uploadedVideos + archiveResults
            
            // Fetch creators and stats in parallel
            async let creatorsTask = fetchCreators(for: uploadedVideos)
            async let statsTask = fetchVideoStats(for: searchResults)
            _ = await [try await creatorsTask, try await statsTask]
            
            // Add archive user for archive videos
            if !archiveResults.isEmpty {
                videoCreators["archive_user"] = archiveUser
            }
            
        } catch {
            searchError = error
            print("Error searching videos: \(error)")
        }
    }
    
    private func searchArchiveVideos(query: String) async -> [Video] {
        do {
            let searchURL = URL(string: "\(InternetArchiveAPI.baseURL)/advancedsearch.php")!
            var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)!
            
            // Build a more targeted search query
            let searchQuery = """
            (title:"\(query)" OR description:"\(query)") AND \
            (mediatype:movies OR mediatype:movingimage) AND \
            -collection:test_videos AND \
            (format:mp4 OR format:h.264 OR format:512kb)
            """
            
            let queryItems = [
                URLQueryItem(name: "q", value: searchQuery),
                URLQueryItem(name: "fl[]", value: "identifier,title,description,downloads"),
                URLQueryItem(name: "output", value: "json"),
                URLQueryItem(name: "rows", value: "25"),
                URLQueryItem(name: "sort[]", value: "-downloads"),
                URLQueryItem(name: "sort[]", value: "-week")
            ]
            
            components.queryItems = queryItems
            print("Archive search URL: \(components.url?.absoluteString ?? "")")
            
            let (data, _) = try await URLSession.shared.data(from: components.url!)
            let searchResponse = try JSONDecoder().decode(ArchiveSearchResponse.self, from: data)
            
            print("Found \(searchResponse.response.docs.count) archive results")
            
            // Fetch stats for all archive videos in parallel
            async let statsSnapshots = db.collection("archive_video_stats")
                .whereField(FieldPath.documentID(), in: searchResponse.response.docs.map { $0.identifier })
                .getDocuments()
            
            // Create a dictionary of video stats
            let stats = try await statsSnapshots.documents.reduce(into: [String: [String: Any]]()) { dict, doc in
                dict[doc.documentID] = doc.data()
            }
            
            // Process videos in parallel using TaskGroup
            return try await withThrowingTaskGroup(of: Video?.self) { group in
                var videos: [Video] = []
                
                // Add tasks for each search result
                for doc in searchResponse.response.docs {
                    group.addTask {
                        // Get the thumbnail URL
                        let thumbnailURL = InternetArchiveAPI.getThumbnailURL(identifier: doc.identifier).absoluteString
                        
                        // Get the actual video URL by checking the file list
                        let videoURL = try await InternetArchiveAPI.getActualVideoURL(identifier: doc.identifier)
                        
                        // Get stats for this video
                        let videoStats = stats[doc.identifier]
                        
                        // Safely convert stats to Int, handling any numeric type from Firestore
                        let views: Int
                        if let viewsValue = videoStats?["views"] {
                            switch viewsValue {
                            case let intValue as Int:
                                views = intValue
                            case let longValue as Int64:
                                views = Int(longValue)
                            case let doubleValue as Double:
                                views = Int(doubleValue)
                            default:
                                views = 0
                            }
                        } else {
                            views = 0
                        }
                        
                        let likes: Int
                        if let likesValue = videoStats?["likes"] {
                            switch likesValue {
                            case let intValue as Int:
                                likes = intValue
                            case let longValue as Int64:
                                likes = Int(longValue)
                            case let doubleValue as Double:
                                likes = Int(doubleValue)
                            default:
                                likes = 0
                            }
                        } else {
                            likes = 0
                        }
                        
                        print("Created archive video: \(doc.title ?? "Untitled") with URL: \(videoURL), views: \(views), likes: \(likes)")
                        
                        return Video(
                            id: nil,
                            archiveIdentifier: doc.identifier,
                            userID: "archive_user",
                            videoURL: videoURL,
                            thumbnailURL: thumbnailURL,
                            caption: doc.title ?? "Untitled",
                            description: doc.description,
                            hashtags: ["archive"],
                            createdAt: Date(),
                            likes: likes,
                            views: views
                        )
                    }
                }
                
                // Collect results
                for try await video in group {
                    if let video = video {
                        videos.append(video)
                    }
                }
                
                return videos
            }
            
        } catch {
            print("Error searching archive videos: \(error.localizedDescription)")
            return []
        }
    }
    
    func searchByText(_ searchText: String) async {
        do {
            // Search in uploaded videos
            let uploadedSnapshot = try await db.collection("videos")
                .whereField("caption", isGreaterThanOrEqualTo: searchText)
                .whereField("caption", isLessThan: searchText + "\u{f8ff}")
                .limit(to: 25)
                .getDocuments()
            
            let uploadedVideos = uploadedSnapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
            
            // Search in archive videos
            let archiveResults = await searchArchiveVideos(query: searchText)
            
            // Combine results
            searchResults = uploadedVideos + archiveResults
            
            // Fetch creators for uploaded videos
            await fetchCreators(for: uploadedVideos)
            
            // Add archive user for archive videos
            if !archiveResults.isEmpty {
                videoCreators["archive_user"] = archiveUser
            }
            
        } catch {
            searchError = error
            print("Error searching videos: \(error)")
        }
    }
    
    func clearSearch() {
        searchResults = []
        searchError = nil
    }
    
    @MainActor
    func updateVideo(_ video: Video, caption: String, hashtags: [String]) async throws {
        guard let videoId = video.id else {
            throw NSError(domain: "VideoFeed", code: 400, userInfo: [NSLocalizedDescriptionKey: "Video ID not found"])
        }
        
        print("Updating video \(videoId) with caption: \(caption), hashtags: \(hashtags)")
        isLoading = true
        do {
            let updates: [String: Any] = [
                "caption": caption,
                "hashtags": hashtags.map { $0.lowercased() }
            ]
            
            try await db.collection("videos").document(videoId).updateData(updates)
            
            // Update local arrays
            if let index = videos.firstIndex(where: { $0.id == videoId }) {
                videos[index].caption = caption
                videos[index].hashtags = hashtags
            }
            
            if let index = searchResults.firstIndex(where: { $0.id == videoId }) {
                searchResults[index].caption = caption
                searchResults[index].hashtags = hashtags
            }
            
            print("Successfully updated video \(videoId)")
            isLoading = false
        } catch {
            print("Error updating video \(videoId): \(error)")
            isLoading = false
            throw error
        }
    }
}