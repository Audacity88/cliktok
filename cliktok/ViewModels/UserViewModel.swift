import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftUI

@MainActor
class UserViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var userVideos: [Video] = []
    @Published var isLoading = false
    @Published var error: Error?
    
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    
    init() {
        Task {
            await fetchCurrentUser()
        }
    }
    
    func fetchCurrentUser() async {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        await fetchUser(userId: userId)
    }
    
    func fetchUser(userId: String) async {
        do {
            let docSnapshot = try await db.collection("users").document(userId).getDocument()
            if let user = try? docSnapshot.data(as: User.self) {
                self.currentUser = user
            }
        } catch {
            self.error = error
            print("Error fetching user: \(error)")
        }
    }
    
    func createUserProfile(username: String, displayName: String, bio: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let now = Timestamp()
        let user = User(
            username: username,
            displayName: displayName,
            bio: bio,
            isPrivateAccount: false,
            balance: 0.0
        )
        
        try await db.collection("users").document(userId).setData([
            "username": username,
            "displayName": displayName,
            "bio": bio,
            "isPrivateAccount": false,
            "balance": 0.0,
            "createdAt": now,
            "updatedAt": now
        ])
        
        currentUser = user
    }
    
    func updateProfile(username: String, displayName: String, bio: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let userData: [String: Any] = [
            "username": username,
            "displayName": displayName,
            "bio": bio,
            "updatedAt": Timestamp()
        ]
        
        try await db.collection("users").document(userId).updateData(userData)
        
        // Update local user object
        if var updatedUser = currentUser {
            updatedUser.username = username
            updatedUser.displayName = displayName
            updatedUser.bio = bio
            currentUser = updatedUser
        }
    }
    
    func uploadProfileImage(_ image: UIImage) async throws -> String? {
        guard let userId = Auth.auth().currentUser?.uid else { return nil }
        guard let imageData = image.jpegData(compressionQuality: 0.8) else { return nil }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let filename = "\(UUID().uuidString).jpg"
            let storageRef = storage.reference().child("profile_images/\(userId)/\(filename)")
            
            _ = try await storageRef.putDataAsync(imageData)
            let url = try await storageRef.downloadURL()
            
            // Update user profile with new image URL
            try await db.collection("users").document(userId).updateData([
                "profileImageURL": url.absoluteString,
                "updatedAt": Timestamp()
            ])
            
            // Update local user object
            if var updatedUser = currentUser {
                updatedUser.profileImageURL = url.absoluteString
                currentUser = updatedUser
            }
            
            return url.absoluteString
        } catch {
            print("Error uploading profile image: \(error)")
            throw error
        }
    }
    
    func togglePrivateAccount() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let currentUser = currentUser else { return }
        
        try await db.collection("users").document(userId).updateData([
            "isPrivateAccount": !currentUser.isPrivateAccount,
            "updatedAt": Timestamp()
        ])
        
        if var updatedUser = self.currentUser {
            updatedUser.isPrivateAccount = !currentUser.isPrivateAccount
            self.currentUser = updatedUser
        }
    }
    
    func fetchUserVideos(for userId: String? = nil) async {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let targetUserId = targetUserId else { return }
        
        do {
            let snapshot = try await db.collection("videos")
                .whereField("user_id", isEqualTo: targetUserId)
                .order(by: "created_at", descending: true)
                .getDocuments()
            
            self.userVideos = snapshot.documents.compactMap { document in
                try? document.data(as: Video.self)
            }
        } catch {
            self.error = error
            print("Error fetching user videos: \(error)")
        }
    }
}
