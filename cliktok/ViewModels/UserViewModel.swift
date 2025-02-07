import Foundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import SwiftUI

@MainActor
class UserViewModel: ObservableObject {
    @Published var currentUser: User?
    @Published var viewedUser: User?
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
        let user = await fetchUserInternal(userId: userId)
        self.currentUser = user
        if user == nil {
            // If no user data exists, create a default profile
            try? await createUserProfile(
                username: "user_\(userId.prefix(6))",
                displayName: "New User",
                bio: "Welcome to my profile!"
            )
        }
    }
    
    func fetchUser(userId: String) async {
        // If fetching current user's profile, update currentUser
        if userId == Auth.auth().currentUser?.uid {
            await fetchCurrentUser()
        } else {
            // If fetching another user's profile, update viewedUser
            viewedUser = await fetchUserInternal(userId: userId)
        }
    }
    
    private func fetchUserInternal(userId: String) async -> User? {
        do {
            let docSnapshot = try await db.collection("users").document(userId).getDocument()
            if let data = docSnapshot.data() {
                return User(
                    id: userId,
                    email: data["email"] as? String ?? Auth.auth().currentUser?.email ?? "",
                    displayName: data["displayName"] as? String ?? "",
                    bio: data["bio"] as? String ?? "",
                    profileImageURL: data["profileImageURL"] as? String,
                    isPrivateAccount: data["isPrivateAccount"] as? Bool ?? false,
                    balance: data["balance"] as? Double ?? 0.0,
                    userRole: UserRole(rawValue: data["userRole"] as? String ?? "") ?? .regular,
                    companyName: data["companyName"] as? String
                )
            }
        } catch {
            self.error = error
            print("Error fetching user: \(error)")
        }
        return nil
    }
    
    func createUserProfile(username: String, displayName: String, bio: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid,
              let email = Auth.auth().currentUser?.email else { return }
        
        let now = Timestamp()
        let user = User(
            id: userId,
            email: email,
            displayName: displayName,
            bio: bio,
            profileImageURL: nil,
            isPrivateAccount: false,
            balance: 0.0
        )
        
        try await db.collection("users").document(userId).setData([
            "email": email,
            "displayName": displayName,
            "bio": bio,
            "isPrivateAccount": false,
            "balance": 0.0,
            "createdAt": now,
            "updatedAt": now,
            "userRole": UserRole.regular.rawValue
        ])
        
        currentUser = user
    }
    
    func updateProfile(displayName: String, bio: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let userData: [String: Any] = [
            "displayName": displayName,
            "bio": bio,
            "updatedAt": Timestamp()
        ]
        
        try await db.collection("users").document(userId).updateData(userData)
        
        // Update local user object
        if var updatedUser = currentUser {
            updatedUser.displayName = displayName
            updatedUser.bio = bio
            currentUser = updatedUser
        }
    }
    
    func fetchUserVideos(for userId: String? = nil) async {
        let targetUserId = userId ?? Auth.auth().currentUser?.uid
        guard let uid = targetUserId else { return }
        
        do {
            let querySnapshot = try await db.collection("videos")
                .whereField("user_id", isEqualTo: uid)
                .order(by: "created_at", descending: true)
                .getDocuments()
            
            userVideos = querySnapshot.documents.compactMap { document in
                let data = document.data()
                return Video(
                    id: document.documentID,
                    userID: data["user_id"] as? String ?? "",
                    videoURL: data["video_url"] as? String ?? "",
                    thumbnailURL: data["thumbnail_url"] as? String,
                    caption: data["caption"] as? String ?? "",
                    hashtags: data["hashtags"] as? [String] ?? [],
                    createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date(),
                    likes: data["likes"] as? Int ?? 0,
                    views: data["views"] as? Int ?? 0,
                    isAdvertisement: data["is_advertisement"] as? Bool ?? false
                )
            }
        } catch {
            print("Error fetching user videos: \(error)")
            self.error = error
        }
    }
    
    func uploadProfileImage(_ image: UIImage) async throws -> String? {
        guard let userId = Auth.auth().currentUser?.uid,
              let imageData = image.jpegData(compressionQuality: 0.7) else { return nil }
        
        let storageRef = storage.reference().child("profile_images/\(userId).jpg")
        _ = try await storageRef.putDataAsync(imageData)
        let downloadURL = try await storageRef.downloadURL()
        
        // Update Firestore with new profile image URL
        try await db.collection("users").document(userId).updateData([
            "profileImageURL": downloadURL.absoluteString,
            "updatedAt": Timestamp()
        ])
        
        // Update local user object
        if var updatedUser = currentUser {
            updatedUser.profileImageURL = downloadURL.absoluteString
            currentUser = updatedUser
        }
        
        return downloadURL.absoluteString
    }
    
    func togglePrivateAccount() async throws {
        guard let userId = Auth.auth().currentUser?.uid,
              let currentUser = currentUser else { return }
        
        let newPrivateStatus = !currentUser.isPrivateAccount
        
        try await db.collection("users").document(userId).updateData([
            "isPrivateAccount": newPrivateStatus,
            "updatedAt": Timestamp()
        ])
        
        // Update local user object
        var updatedUser = currentUser
        updatedUser.isPrivateAccount = newPrivateStatus
        self.currentUser = updatedUser
    }
}
