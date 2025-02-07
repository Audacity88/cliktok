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
            print("VideoUploadViewModel: isUserMarketer changed to: \(isUserMarketer)")
        }
    }
    
    var onUploadComplete: (() -> Void)?
    private var cancellables = Set<AnyCancellable>()
    
    private let storage = Storage.storage()
    private let db = Firestore.firestore()
    private let logger = Logger(subsystem: "gauntletai.cliktok", category: "VideoUploadViewModel")
    private let authManager = AuthenticationManager.shared
    
    init() {
        print("VideoUploadViewModel: Initializing...")
        // Set initial marketer status
        isUserMarketer = authManager.isMarketer
        print("VideoUploadViewModel: Initial marketer status set to: \(isUserMarketer)")
        
        // Observe changes to marketer status using Combine
        NotificationCenter.default
            .publisher(for: .init("UserRoleChanged"))
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                print("VideoUploadViewModel: Received UserRoleChanged notification")
                self.isUserMarketer = self.authManager.isMarketer
                print("VideoUploadViewModel: Updated marketer status to: \(self.isUserMarketer)")
            }
            .store(in: &cancellables)
    }
    
    func checkMarketerStatus() {
        print("VideoUploadViewModel: Checking marketer status...")
        let oldValue = isUserMarketer
        isUserMarketer = authManager.isMarketer
        print("VideoUploadViewModel: Marketer status changed from \(oldValue) to \(isUserMarketer)")
    }
    
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
                hashtags: hashtags,
                isAdvertisement: isUserMarketer && isAdvertisement ? true : nil
            )
            
            // Create document reference with auto-generated ID and set data
            let docRef = db.collection("videos").document()
            let data = try Firestore.Encoder().encode(video)
            try await docRef.setData(data)
            
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
            _ = thumbnailRef.putData(thumbnailData, metadata: metadata) { metadata, error in
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
            let uploadTask = storageRef.putFile(from: videoURL, metadata: metadata) { metadata, error in
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
            
            uploadTask.observe(.progress) { [weak self] snapshot in
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
        
        // Get thumbnail from first frame
        let cgImage = try await imageGenerator.image(at: .zero).image
        
        // Convert CGImage to UIImage
        let thumbnail = UIImage(cgImage: cgImage)
        
        // Create temporary URL for thumbnail
        let temporaryDirectory = FileManager.default.temporaryDirectory
        let thumbnailURL = temporaryDirectory.appendingPathComponent(UUID().uuidString + ".jpg")
        
        // Write thumbnail to temporary file
        if let thumbnailData = thumbnail.jpegData(compressionQuality: 0.8) {
            try thumbnailData.write(to: thumbnailURL)
            return thumbnailURL
        } else {
            throw NSError(domain: "ThumbnailGeneration", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to generate thumbnail data"])
        }
    }
}