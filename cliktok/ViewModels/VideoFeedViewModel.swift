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
        id: "archive_user",
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
        // Add archive user to creators
        videoCreators["archive_user"] = archiveUser
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
            isLoading = false
            
            // Fetch creators for these videos
            await fetchCreators(for: videos)
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
            isLoading = false
            
            // Fetch creators for new videos
            await fetchCreators(for: newVideos)
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
                        let data = docSnapshot.data()
                        print("Raw user data: \(String(describing: data))")
                        
                        // Manual decoding
                        if let data = data {
                            let user = User(
                                id: creatorId,
                                email: data["email"] as? String ?? "",
                                username: data["username"] as? String ?? "",
                                displayName: data["displayName"] as? String ?? "",
                                bio: data["bio"] as? String ?? "",
                                profileImageURL: data["profileImageURL"] as? String,
                                isPrivateAccount: data["isPrivateAccount"] as? Bool ?? false,
                                balance: data["balance"] as? Double ?? 0.0,
                                userRole: UserRole(rawValue: data["userRole"] as? String ?? "") ?? .regular,
                                companyName: data["companyName"] as? String
                            )
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
    
    func updateVideoStats(video: Video, liked: Bool? = nil, viewed: Bool = true) async {
        // For archive videos, use the archive identifier
        let documentId: String
        if video.userID == "archive_user" {
            if let archiveId = video.archiveIdentifier {
                documentId = archiveId
            } else if let id = video.id {
                documentId = id.replacingOccurrences(of: "archive_", with: "")
            } else {
                return
            }
        } else {
            guard let id = video.id else { return }
            documentId = id
        }
        
        do {
            var updates: [String: Any] = [:]
            
            if viewed {
                updates["views"] = FieldValue.increment(Int64(1))
                // Update local video object
                if let index = videos.firstIndex(where: { $0.id == video.id }) {
                    videos[index].views += 1
                }
                if let index = searchResults.firstIndex(where: { $0.id == video.id }) {
                    searchResults[index].views += 1
                }
            }
            
            if let liked = liked {
                updates["likes"] = FieldValue.increment(Int64(liked ? 1 : -1))
            }
            
            if !updates.isEmpty {
                print("Updating video stats for \(documentId) with updates: \(updates)")
                
                // Use different collection based on video type
                let collectionPath = video.userID == "archive_user" ? "archive_video_stats" : "videos"
                
                if video.userID == "archive_user" {
                    // For archive videos, create or update the stats document
                    let statsRef = db.collection(collectionPath).document(documentId)
                    // First check if document exists
                    let docSnapshot = try await statsRef.getDocument()
                    if docSnapshot.exists {
                        try await statsRef.updateData(updates)
                    } else {
                        try await statsRef.setData(updates)
                    }
                } else {
                    // For regular videos, update the video document
                    try await db.collection(collectionPath).document(documentId).updateData(updates)
                }
                
                print("Successfully updated video stats")
            }
        } catch {
            print("Error updating video stats: \(error.localizedDescription)")
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
                            id: "archive_\(doc.identifier)",
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