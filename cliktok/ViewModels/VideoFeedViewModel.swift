import Foundation
import FirebaseFirestore
import Combine

@MainActor
class VideoFeedViewModel: ObservableObject {
    @Published var videos: [Video] = []
    @Published var isLoading = false
    @Published var error: Error?
    
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
        } catch {
            self.error = error
            isLoading = false
        }
    }
    
    func loadMoreVideos() async {
        guard !isLoading, let lastDocument = lastDocument else { return }
        
        isLoading = true
        do {
            let snapshot = try await db.collection("videos")
                .order(by: "created_at", descending: true)
                .start(afterDocument: lastDocument)
                .limit(to: pageSize)
                .getDocuments()
            
            let newVideos = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
            
            videos.append(contentsOf: newVideos)
            self.lastDocument = snapshot.documents.last
            isLoading = false
        } catch {
            self.error = error
            isLoading = false
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
} 