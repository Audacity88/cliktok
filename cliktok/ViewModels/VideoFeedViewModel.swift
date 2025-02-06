import Foundation
import FirebaseFirestore
import Combine

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var error: Error?
    @Published var videoCreators: [String: User] = [:]
    
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
                                username: data["username"] as? String ?? "",
                                displayName: data["displayName"] as? String ?? "",
                                bio: data["bio"] as? String ?? "",
                                profileImageURL: data["profileImageURL"] as? String,
                                isPrivateAccount: data["isPrivateAccount"] as? Bool ?? false,
                                balance: data["balance"] as? Double
                            )
                            print("Successfully created user: \(user.displayName)")
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
        let creator = videoCreators[video.userID]
        print("Getting creator for video \(video.id): \(creator?.displayName ?? "not found")")
        return creator
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
}