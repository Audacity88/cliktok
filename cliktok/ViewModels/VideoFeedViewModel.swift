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
    
    private var lastDocument: DocumentSnapshot?
    private let pageSize = 5
    private let db = Firestore.firestore()
    
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
            }
            
            if let liked = liked {
                updates["likes"] = FieldValue.increment(Int64(liked ? 1 : -1))
            }
            
            if !updates.isEmpty {
                try await db.collection("videos").document(id).updateData(updates)
            }
        } catch {
            print("Error updating video stats: \(error.localizedDescription)")
        }
    }
    
    func searchVideos(hashtag: String) async {
        do {
            let snapshot = try await db.collection("videos")
                .whereField("hashtags", arrayContains: hashtag)
                .limit(to: 50)
                .getDocuments()
            
            searchResults = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
            
            // Fetch creators for these videos
            await fetchCreators(for: searchResults)
            
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