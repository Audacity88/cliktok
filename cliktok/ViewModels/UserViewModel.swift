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
    @Published var usernameError: String?
    
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
                return try docSnapshot.data(as: User.self)
            }
        } catch {
            self.error = error
            print("Error fetching user: \(error)")
        }
        return nil
    }
    
    func isUsernameAvailable(_ username: String) async -> Bool {
        do {
            let snapshot = try await db.collection("users")
                .whereField("username", isEqualTo: username)
                .getDocuments()
            return snapshot.documents.isEmpty
        } catch {
            print("Error checking username availability: \(error)")
            return false
        }
    }
    
    func validateUsername(_ username: String) -> Bool {
        // Username must be 3-20 characters, alphanumeric with underscores only
        let usernameRegex = "^[a-zA-Z0-9_]{3,20}$"
        let usernamePredicate = NSPredicate(format: "SELF MATCHES %@", usernameRegex)
        return usernamePredicate.evaluate(with: username)
    }
    
    func updateUsername(_ newUsername: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        // Reset error
        usernameError = nil
        
        // Validate username format
        guard validateUsername(newUsername) else {
            usernameError = "Username must be 3-20 characters and contain only letters, numbers, and underscores"
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: usernameError!])
        }
        
        // Check availability
        guard await isUsernameAvailable(newUsername) else {
            usernameError = "Username is already taken"
            throw NSError(domain: "", code: -1, userInfo: [NSLocalizedDescriptionKey: usernameError!])
        }
        
        let userData: [String: Any] = [
            "username": newUsername,
            "updatedAt": Timestamp()
        ]
        
        try await db.collection("users").document(userId).updateData(userData)
        
        // Update local user object
        if var updatedUser = currentUser {
            updatedUser.username = newUsername
            currentUser = updatedUser
        }
    }
    
    func createUserProfile(username: String, displayName: String, bio: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid,
              let email = Auth.auth().currentUser?.email else { return }
        
        let now = Timestamp()
        let user = User(
            id: userId,
            email: email,
            username: username,
            displayName: displayName,
            bio: bio,
            profileImageURL: nil,
            isPrivateAccount: false,
            balance: 0.0
        )
        
        try await db.collection("users").document(userId).setData([
            "email": email,
            "username": username,
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
    
    func updateUserRole(asMarketer: Bool, companyName: String?) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        var userData: [String: Any] = [
            "userRole": asMarketer ? UserRole.marketer.rawValue : UserRole.regular.rawValue,
            "updatedAt": Timestamp()
        ]
        
        if let companyName = companyName {
            userData["companyName"] = companyName
        } else if !asMarketer {
            // Remove company name if switching back to regular user
            userData["companyName"] = FieldValue.delete()
        }
        
        try await db.collection("users").document(userId).updateData(userData)
        
        // Update local user object
        if var updatedUser = currentUser {
            updatedUser.userRole = asMarketer ? .marketer : .regular
            updatedUser.companyName = companyName
            currentUser = updatedUser
            
            // Update AuthenticationManager
            AuthenticationManager.shared.isMarketer = asMarketer
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
                    archiveIdentifier: nil,
                    userID: data["user_id"] as? String ?? "",
                    videoURL: data["video_url"] as? String ?? "",
                    thumbnailURL: data["thumbnail_url"] as? String,
                    caption: data["caption"] as? String ?? "",
                    description: data["description"] as? String,
                    hashtags: data["hashtags"] as? [String] ?? [],
                    createdAt: (data["created_at"] as? Timestamp)?.dateValue() ?? Date(),
                    likes: data["likes"] as? Int ?? 0,
                    views: data["views"] as? Int ?? 0,
                    isAdvertisement: data["is_advertisement"] as? Bool
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
        
        let storageRef = storage.reference().child("profile_images").child(userId)
        
        do {
            // Upload the image data
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            _ = try await storageRef.putDataAsync(imageData, metadata: metadata)
            
            // Get the download URL
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
        } catch {
            print("Error uploading profile image: \(error)")
            throw error
        }
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
