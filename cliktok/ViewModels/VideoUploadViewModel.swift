import Foundation
import FirebaseStorage
import FirebaseFirestore
import PhotosUI
import AVFoundation
import OSLog

@MainActor
class VideoUploadViewModel: ObservableObject {
    @Published var isUploading = false
    @Published var progress: Double = 0
    @Published var error: Error?
    var onUploadComplete: (() -> Void)?
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private let logger = Logger(subsystem: "com.cliktok", category: "VideoUploadViewModel")
    
    func uploadVideo(videoURL: URL, caption: String, hashtags: [String]) async throws {
        guard let userID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "VideoUpload", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isUploading = true
        progress = 0
        error = nil
        
        do {
            // Generate unique filenames for video and thumbnail
            let videoFilename = "\(UUID().uuidString).mp4"
            let thumbnailFilename = "\(UUID().uuidString).jpg"
            
            let storageRef = storage.reference().child("videos/\(userID)/\(videoFilename)")
            let thumbnailRef = storage.reference().child("thumbnails/\(userID)/\(thumbnailFilename)")
            
            // Create and upload thumbnail
            let thumbnailURL = try await generateThumbnail(from: videoURL)
            let thumbnailData = try Data(contentsOf: thumbnailURL)
            let uploadedThumbnailURL = try await uploadThumbnail(thumbnailRef: thumbnailRef, thumbnailData: thumbnailData)
            
            // Upload video
            let uploadedVideoURL = try await uploadVideo(storageRef: storageRef, videoURL: videoURL)
            
            // Create video document in Firestore
            let video = Video(
                userID: userID,
                videoURL: uploadedVideoURL.absoluteString,
                thumbnailURL: uploadedThumbnailURL.absoluteString,
                caption: caption,
                hashtags: hashtags
            )
            
            try await db.collection("videos").document().setData(from: video)
            
            isUploading = false
            progress = 1.0
            
            // Notify that upload is complete
            await MainActor.run {
                onUploadComplete?()
            }
            
        } catch {
            isUploading = false
            self.error = error
            throw error
        }
    }
    
    private func uploadThumbnail(thumbnailRef: StorageReference, thumbnailData: Data) async throws -> URL {
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = thumbnailRef.putData(thumbnailData, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                Task {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        let url = try await thumbnailRef.downloadURL()
                        continuation.resume(returning: url)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func uploadVideo(storageRef: StorageReference, videoURL: URL) async throws -> URL {
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = storageRef.putFile(from: videoURL, metadata: metadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                Task {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        let url = try await storageRef.downloadURL()
                        continuation.resume(returning: url)
                    } catch {
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            task.observe(.progress) { [weak self] snapshot in
                guard let self = self else { return }
                let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1)
                DispatchQueue.main.async {
                    self.progress = percentComplete
                }
            }
        }
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        imageGenerator.maximumSize = CGSize(width: 1280, height: 720) // HD size is sufficient for thumbnails
        
        // Generate thumbnail from first frame
        let time = CMTime(seconds: 0, preferredTimescale: 600)
        let cgImage = try await imageGenerator.image(at: time).image
        
        // Convert to UIImage and compress
        let thumbnail = UIImage(cgImage: cgImage)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else {
            throw NSError(domain: "VideoUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create thumbnail data"])
        }
        
        try data.write(to: tempURL)
        return tempURL
    }
} 