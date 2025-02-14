import Foundation
import FirebaseStorage
import FirebaseFirestore
import PhotosUI
import AVFoundation
import OSLog
import Combine

@MainActor
class VideoUploadViewModel: ObservableObject {
    @Published var isUploading = false
    @Published var progress: Double = 0
    @Published var error: Error?
    @Published var isAdvertisement = false
    @Published var isUserMarketer = false {
        didSet {
            logger.debug("👥 Marketer status changed to: \(isUserMarketer)")
        }
    }
    
    var onUploadComplete: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private let logger = Logger(component: "VideoUploadViewModel")
    private let authManager = AuthenticationManager.shared
    
    init() {
        logger.info("🎥 Initializing VideoUploadViewModel")
        // Set initial marketer status
        isUserMarketer = authManager.isMarketer
        logger.debug("👥 Initial marketer status set to: \(isUserMarketer)")
        
        // Observe changes to marketer status using Combine
        NotificationCenter.default
            .publisher(for: .init("UserRoleChanged"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                logger.debug("📢 Received UserRoleChanged notification")
                self.isUserMarketer = self.authManager.isMarketer
                logger.debug("👥 Updated marketer status to: \(self.isUserMarketer)")
            }
            .store(in: &cancellables)
    }
    
    func checkMarketerStatus() {
        logger.debug("🔍 Checking marketer status...")
        let oldValue = isUserMarketer
        isUserMarketer = authManager.isMarketer
        logger.debug("👥 Marketer status changed from \(oldValue) to \(isUserMarketer)")
    }
    
    func uploadVideo(videoURL: URL, caption: String, hashtags: [String]) async throws {
        guard let userID = AuthenticationManager.shared.currentUser?.uid else {
            logger.error("❌ No authenticated user found")
            throw NSError(domain: "UploadError", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isUploading = true
        progress = 0
        error = nil
        logger.info("📤 Starting video upload for user: \(userID)")
        
        do {
            // Generate unique filenames for video and thumbnail
            let videoFilename = "\(UUID().uuidString).mp4"
            let thumbnailFilename = "\(UUID().uuidString).jpg"
            logger.debug("🎯 Generated filenames - Video: \(videoFilename), Thumbnail: \(thumbnailFilename)")
            
            let storageRef = storage.reference().child("videos/\(userID)/\(videoFilename)")
            let thumbnailRef = storage.reference().child("thumbnails/\(userID)/\(thumbnailFilename)")
            logger.debug("📁 Created storage references")
            
            // Create and upload thumbnail
            logger.debug("🖼️ Generating thumbnail...")
            let thumbnailURL = try await generateThumbnail(from: videoURL)
            let thumbnailData = try Data(contentsOf: thumbnailURL)
            logger.debug("📤 Uploading thumbnail...")
            let uploadedThumbnailURL = try await uploadThumbnail(thumbnailRef: thumbnailRef, thumbnailData: thumbnailData)
            logger.success("✅ Thumbnail uploaded successfully")
            
            // Upload video
            logger.debug("📤 Starting video upload...")
            let uploadedVideoURL = try await uploadVideo(storageRef: storageRef, videoURL: videoURL)
            logger.success("✅ Video uploaded successfully")
            
            // Create video document in Firestore
            let video = Video(
                id: nil,
                archiveIdentifier: nil,
                userID: userID,
                videoURL: uploadedVideoURL.absoluteString,
                thumbnailURL: uploadedThumbnailURL.absoluteString,
                caption: caption,
                description: nil,
                hashtags: hashtags,
                createdAt: Date(),
                likes: 0,
                views: 0,
                isAdvertisement: isUserMarketer && isAdvertisement ? true : nil
            )
            
            logger.debug("💾 Creating video document in Firestore...")
            let docRef = db.collection("videos").document()
            let data = try Firestore.Encoder().encode(video)
            try await docRef.setData(data)
            logger.success("✅ Video document created successfully")
            
            isUploading = false
            progress = 1.0
            
            logger.success("🎉 Upload process completed successfully")
            
            // Notify that upload is complete
            await MainActor.run {
                onUploadComplete?()
            }
            
        } catch {
            isUploading = false
            self.error = error
            logger.error("❌ Upload failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    private func uploadThumbnail(thumbnailRef: StorageReference, thumbnailData: Data) async throws -> URL {
        logger.debug("📤 Starting thumbnail upload...")
        let metadata = StorageMetadata()
        metadata.contentType = "image/jpeg"
        
        return try await withCheckedThrowingContinuation { continuation in
            _ = thumbnailRef.putData(thumbnailData, metadata: metadata) { [self] metadata, error in
                if let error = error {
                    self.logger.error("❌ Thumbnail upload failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                Task { [self] in
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        let url = try await thumbnailRef.downloadURL()
                        self.logger.debug("🔗 Got thumbnail download URL: \(url)")
                        continuation.resume(returning: url)
                    } catch {
                        self.logger.error("❌ Failed to get thumbnail download URL: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
    
    private func uploadVideo(storageRef: StorageReference, videoURL: URL) async throws -> URL {
        logger.debug("📤 Starting video file upload...")
        let metadata = StorageMetadata()
        metadata.contentType = "video/mp4"
        
        return try await withCheckedThrowingContinuation { continuation in
            let uploadTask = storageRef.putFile(from: videoURL, metadata: metadata) { [self] metadata, error in
                if let error = error {
                    self.logger.error("❌ Video upload failed: \(error.localizedDescription)")
                    continuation.resume(throwing: error)
                    return
                }
                
                Task { [self] in
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                        let url = try await storageRef.downloadURL()
                        self.logger.debug("🔗 Got video download URL: \(url)")
                        continuation.resume(returning: url)
                    } catch {
                        self.logger.error("❌ Failed to get video download URL: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
            
            uploadTask.observe(.progress) { [weak self] snapshot in
                guard let self = self else { return }
                let percentComplete = Double(snapshot.progress?.completedUnitCount ?? 0) / Double(snapshot.progress?.totalUnitCount ?? 1)
                DispatchQueue.main.async {
                    self.progress = percentComplete
                    self.logger.debug("📊 Upload progress: \(Int(percentComplete * 100))%")
                }
            }
        }
    }
    
    private func generateThumbnail(from videoURL: URL) async throws -> URL {
        logger.debug("🖼️ Starting thumbnail generation...")
        let asset = AVURLAsset(url: videoURL)
        let imageGenerator = AVAssetImageGenerator(asset: asset)
        imageGenerator.appliesPreferredTrackTransform = true
        
        do {
            // Get thumbnail from first frame
            let cgImage = try await imageGenerator.image(at: .zero).image
            logger.debug("✅ Generated thumbnail image")
            
            // Convert CGImage to UIImage
            let thumbnail = UIImage(cgImage: cgImage)
            
            // Create temporary URL for thumbnail
            let temporaryDirectory = FileManager.default.temporaryDirectory
            let thumbnailURL = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
            
            // Write thumbnail to temporary file
            if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
                try thumbnailData.write(to: thumbnailURL)
                logger.success("✅ Saved thumbnail to temporary file: \(thumbnailURL.lastPathComponent)")
                return thumbnailURL
            } else {
                logger.error("❌ Failed to generate thumbnail data")
                throw NSError(domain: "ThumbnailGeneration", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail data"])
            }
        } catch {
            logger.error("❌ Thumbnail generation failed: \(error.localizedDescription)")
            throw error
        }
    }
    
    deinit {
        logger.debug("🎥 VideoUploadViewModel deinitializing")
    }
}