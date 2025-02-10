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
        guard let id = video.id else { return }
        
        do {
            var updates: [String: Any] = [:]
            
            if viewed {
                updates["views"] = FieldValue.increment(Int64(1))
                // Update local video object
                if let index = videos.firstIndex(where: { $0.id == id }) {
                    videos[index].views += 1
                }
                if let index = searchResults.firstIndex(where: { $0.id == id }) {
                    searchResults[index].views += 1
                }
            }
            
            if let liked = liked {
                updates["likes"] = FieldValue.increment(Int64(liked ? 1 : -1))
            }
            
            if !updates.isEmpty {
                print("Updating video stats for \(id) with updates: \(updates)")
                try await db.collection("videos").document(id).updateData(updates)
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
            
            return searchResponse.response.docs.compactMap { doc in
                // Get the thumbnail URL
                let thumbnailURL = InternetArchiveAPI.getThumbnailURL(identifier: doc.identifier).absoluteString
                
                // Try different video formats in order of preference
                let possibleFilenames = [
                    "\(doc.identifier)_512kb.mp4",
                    "\(doc.identifier).mp4",
                    "\(doc.identifier)_h264.mp4"
                ]
                
                let videoURL = possibleFilenames
                    .map { InternetArchiveAPI.getVideoURL(identifier: doc.identifier, filename: $0) }
                    .first?
                    .absoluteString ?? ""
                
                guard !videoURL.isEmpty else {
                    print("No valid video URL found for \(doc.identifier)")
                    return nil
                }
                
                print("Created archive video: \(doc.title ?? "Untitled") with URL: \(videoURL)")
                
                return Video(
                    id: doc.identifier,
                    userID: "archive_user",
                    videoURL: videoURL,
                    thumbnailURL: thumbnailURL,
                    caption: doc.title ?? "Untitled",
                    description: doc.description,
                    hashtags: ["archive"],
                    createdAt: Date(),
                    likes: 0,
                    views: 0
                )
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