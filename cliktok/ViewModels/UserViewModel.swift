import Foundation
import FirebaseFirestore
import FirebaseStorage
import FirebaseAuth
import SwiftUI

@MainActor
class UserViewModel: ObservableObject {
    @Published var currentUser: User?
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
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No authenticated user found")
            return
        }
        
        do {
            let docSnapshot = try await db.collection("users").document(userId).getDocument()
            if let user = try? docSnapshot.data(as: User.self) {
                self.currentUser = user
            } else {
                // If user document doesn't exist, create it
                try await createUserProfile()
            }
        } catch {
            self.error = error
            print("Error fetching user: \(error)")
        }
    }
    
    func updateProfile(username: String, displayName: String, bio: String) async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        
        let data: [String: Any] = [
            "username": username,
            "displayName": displayName,
            "bio": bio,
            "updatedAt": Date()
        ]
        
        try await db.collection("users").document(userId).updateData(data)
        await fetchCurrentUser()
    }
    
    func uploadProfileImage(_ image: UIImage) async throws -> String? {
        guard let userId = Auth.auth().currentUser?.uid else {
            print("No authenticated user found during upload")
            throw NSError(domain: "AuthError", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Print auth state for debugging
            print("Current auth state - User ID: \(userId)")
            print("Current auth state - Token: \(String(describing: try? await Auth.auth().currentUser?.getIDToken()))")
            
            // Resize image if needed
            let maxSize: CGFloat = 1024 // 1024x1024 max
            let resizedImage: UIImage
            if image.size.width > maxSize || image.size.height > maxSize {
                let scale = maxSize / max(image.size.width, image.size.height)
                let newSize = CGSize(width: image.size.width * scale, height: image.size.height * scale)
                UIGraphicsBeginImageContextWithOptions(newSize, false, 1.0)
                image.draw(in: CGRect(origin: .zero, size: newSize))
                resizedImage = UIGraphicsGetImageFromCurrentImageContext() ?? image
                UIGraphicsEndImageContext()
            } else {
                resizedImage = image
            }
            
            guard let resizedImageData = resizedImage.jpegData(compressionQuality: 0.7) else {
                throw NSError(domain: "ImageError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Failed to compress image"])
            }
            
            let metadata = StorageMetadata()
            metadata.contentType = "image/jpeg"
            
            // Create storage reference
            let storageRef = storage.reference()
            let profileImagesRef = storageRef.child("profile_images")
            let imageRef = profileImagesRef.child("\(userId).jpg")
            
            print("Uploading to path: \(imageRef.fullPath)")
            
            // Upload the image
            let _ = try await imageRef.putDataAsync(resizedImageData, metadata: metadata)
            let url = try await imageRef.downloadURL()
            
            print("Successfully uploaded image to: \(url.absoluteString)")
            
            // Update user profile with new image URL
            try await db.collection("users").document(userId).updateData([
                "profileImageURL": url.absoluteString,
                "updatedAt": Date()
            ])
            
            return url.absoluteString
        } catch {
            print("Error in uploadProfileImage: \(error)")
            self.error = error
            throw error
        }
    }
    
    func createUserProfile() async throws {
        guard let firebaseUser = Auth.auth().currentUser else { return }
        
        let username = firebaseUser.email?.components(separatedBy: "@")[0] ?? "user_\(firebaseUser.uid.prefix(6))"
        
        let newUser = User(
            id: firebaseUser.uid,
            username: username,
            displayName: username,
            bio: "",
            profileImageURL: nil,
            createdAt: Date(),
            updatedAt: Date(),
            isPrivateAccount: false
        )
        
        try await db.collection("users").document(firebaseUser.uid).setData(from: newUser)
        self.currentUser = newUser
    }
    
    func togglePrivateAccount() async throws {
        guard let userId = Auth.auth().currentUser?.uid else { return }
        guard let currentUser = currentUser else { return }
        
        try await db.collection("users").document(userId).updateData([
            "isPrivateAccount": !currentUser.isPrivateAccount,
            "updatedAt": Date()
        ])
        
        await fetchCurrentUser()
    }
}
