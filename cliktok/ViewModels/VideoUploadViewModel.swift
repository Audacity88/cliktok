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
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private let logger = Logger(subsystem: "com.cliktok", category: "VideoUploadViewModel")
    private let maxRetries = 3
    private var currentUploadTask: StorageUploadTask?
    
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
            
            // Create and upload thumbnail first
            logger.debug("Generating thumbnail...")
            let thumbnailURL = try await generateThumbnail(from: videoURL)
            let thumbnailData = try Data(contentsOf: thumbnailURL)
            
            // Upload thumbnail with retries
            var thumbnailDownloadURL: URL?
            for attempt in 1...self.maxRetries {
                do {
                    logger.debug("Attempting thumbnail upload (attempt \(attempt)/\(self.maxRetries))")
                    // Cancel any existing upload task
                    currentUploadTask?.cancel()
                    thumbnailDownloadURL = try await uploadThumbnail(thumbnailRef: thumbnailRef, thumbnailData: thumbnailData)
                    break
                } catch {
                    if attempt == self.maxRetries {
                        throw error
                    }
                    logger.error("Thumbnail upload attempt \(attempt) failed: \(error.localizedDescription)")
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                }
            }
            
            guard let uploadedThumbnailURL = thumbnailDownloadURL else {
                throw NSError(domain: "VideoUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to upload thumbnail"])
            }
            
            // Upload video with retries
            var videoDownloadURL: URL?
            for attempt in 1...self.maxRetries {
                do {
                    logger.debug("Attempting video upload (attempt \(attempt)/\(self.maxRetries))")
                    // Cancel any existing upload task
                    currentUploadTask?.cancel()
                    videoDownloadURL = try await uploadVideo(storageRef: storageRef, videoURL: videoURL)
                    break
                } catch {
                    if attempt == self.maxRetries {
                        throw error
                    }
                    logger.error("Video upload attempt \(attempt) failed: \(error.localizedDescription)")
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(attempt)) * 1_000_000_000))
                }
            }
            
            guard let uploadedVideoURL = videoDownloadURL else {
                throw NSError(domain: "VideoUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to upload video"])
            }
            
            // Create video document in Firestore
            let video = Video(
                userID: userID,
                videoURL: uploadedVideoURL.absoluteString,
                thumbnailURL: uploadedThumbnailURL.absoluteString,
                caption: caption,
                hashtags: hashtags
            )
            
            try await db.collection("videos").document().setData(from: video)
            logger.debug("Video document created in Firestore")
            
            isUploading = false
            progress = 1.0
            logger.debug("Video upload completed successfully")
            
        } catch {
            isUploading = false
            self.error = error
            logger.error("Video upload failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func uploadThumbnail(thumbnailRef: StorageReference, thumbnailData: Data) async throws -> URL {
        let uploadMetadata = StorageMetadata()
        uploadMetadata.contentType = "image/jpeg"
        
        logger.debug("Thumbnail upload metadata: \(uploadMetadata)")
        
        return try await withCheckedThrowingContinuation { continuation in
            logger.debug("Starting thumbnail upload...")
            
            let task = thumbnailRef.putData(thumbnailData, metadata: uploadMetadata) { metadata, error in
                if let error = error {
                    self.logger.error("\(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                self.logger.debug("Thumbnail upload putData completed, waiting before getting URL...")
                
                // Wait a short moment before getting the download URL
                Task {
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        let url = try await thumbnailRef.downloadURL()
                        self.logger.debug("Got thumbnail URL: \(url)")
                        continuation.resume(returning: url)
                    } catch {
                        self.logger.error("\(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            self.currentUploadTask = task
        }
    }
    
    private func uploadVideo(storageRef: StorageReference, videoURL: URL) async throws -> URL {
        let uploadMetadata = StorageMetadata()
        uploadMetadata.contentType = "video/mp4"
        
        return try await withCheckedThrowingContinuation { continuation in
            let task = storageRef.putFile(from: videoURL, metadata: uploadMetadata) { metadata, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                
                // Wait a short moment before getting the download URL
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
            
            self.currentUploadTask = task
        }
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        // Get thumbnail from first frame
        logger.debug("Generating thumbnail from video frame...")
        let cgImage = try await imageGenerator.image(at: .zero).image
        
        // Convert CGImage to UIImage
        logger.debug("Converting CGImage to UIImage...")
        let thumbnail = UIImage(cgImage: cgImage)
        
        // Save to temporary file
        logger.debug("Saving thumbnail to temporary file...")
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        guard let data = thumbnail.jpegData(compressionQuality: 0.8) else {
            let error = NSError(domain: "VideoUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to create thumbnail data"])
            logger.error("\(error.localizedDescription)")
            throw error
        }
        
        logger.debug("Writing thumbnail data to file...")
        try data.write(to: tempURL)
        
        logger.debug("Thumbnail generated successfully at: \(tempURL)")
        return tempURL
    }
} 