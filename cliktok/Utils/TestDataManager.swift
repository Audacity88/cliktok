import Foundation
import FirebaseFirestore
import FirebaseStorage
import OSLog

enum TestDataError: LocalizedError {
    case networkError
    case firestoreError(Error)
    case firebaseNotInitialized
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection is unavailable"
        case .firestoreError(let error):
            return "Firebase error: \(error.localizedDescription)"
        case .firebaseNotInitialized:
            return "Firebase is not properly initialized"
        }
    }
}

class TestDataManager {
    static let shared = TestDataManager()
    private let db = Firestore.firestore()
    private let storage = Storage.storage()
    private let maxRetries = 3
    private let logger = Logger(subsystem: "com.cliktok", category: "TestDataManager")
    
    func testFirebaseConnection() async throws {
        self.logger.debug("Testing Firebase connection...")
        
        // Test document
        let testDoc = [
            "test": true,
            "timestamp": FieldValue.serverTimestamp()
        ] as [String : Any]
        
        do {
            // Try to write a test document
            self.logger.debug("Attempting to write test document...")
            let docRef = try await self.db.collection("test").addDocument(data: testDoc)
            self.logger.debug("Test document written successfully")
            
            // Try to read it back
            self.logger.debug("Attempting to read test document...")
            let _ = try await docRef.getDocument()
            self.logger.debug("Test document read successfully")
            
            // Clean up
            self.logger.debug("Cleaning up test document...")
            try await docRef.delete()
            self.logger.debug("Test document deleted successfully")
            
            self.logger.debug("Firebase connection test completed successfully")
        } catch {
            self.logger.error("Firebase connection test failed: \(error.localizedDescription)")
            throw TestDataError.firestoreError(error)
        }
    }
    
    func addSampleVideo() async throws {
        self.logger.debug("Adding single sample video")
        try await addVideoWithRetry {
            // Sample video URL (using a royalty-free video)
            let sampleVideoURL = "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4"
            
            // Create sample video document
            let video = Video(
                id: nil,
                userID: "test_user",
                videoURL: sampleVideoURL,
                thumbnailURL: nil,
                caption: "Sample Video - Big Buck Bunny",
                hashtags: ["sample", "test", "bunny"],
                createdAt: Date(),
                likes: 0,
                views: 0
            )
            
            self.logger.debug("Attempting to add document to Firestore")
            // Add to Firestore
            try await self.db.collection("videos").addDocument(from: video)
            self.logger.debug("Sample video added successfully!")
        }
    }
    
    func addMultipleSampleVideos(count: Int = 5) async throws {
        self.logger.debug("Adding \(count) sample videos")
        let sampleVideos = [
            "https://storage.googleapis.com/gtv-videos-bucket/sample/BigBuckBunny.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ElephantsDream.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerEscapes.mp4",
            "https://storage.googleapis.com/gtv-videos-bucket/sample/ForBiggerFun.mp4"
        ]
        
        for i in 0..<count {
            self.logger.debug("Adding video \(i + 1) of \(count)")
            try await addVideoWithRetry {
                let videoURL = sampleVideos[i % sampleVideos.count]
                let video = Video(
                    id: nil,
                    userID: "test_user",
                    videoURL: videoURL,
                    thumbnailURL: nil,
                    caption: "Sample Video #\(i + 1)",
                    hashtags: ["sample", "test", String(i + 1)],
                    createdAt: Date(),
                    likes: Int.random(in: 0...100),
                    views: Int.random(in: 100...1000)
                )
                
                self.logger.debug("Attempting to add video \(i + 1) to Firestore")
                try await self.db.collection("videos").addDocument(from: video)
                self.logger.debug("Added sample video #\(i + 1)")
            }
        }
        
        self.logger.debug("All sample videos added successfully!")
    }
    
    private func addVideoWithRetry(_ operation: () async throws -> Void) async throws {
        guard NetworkMonitor.shared.isConnected else {
            self.logger.error("Network is not connected")
            throw TestDataError.networkError
        }
        
        var lastError: Error?
        for attempt in 1...self.maxRetries {
            do {
                self.logger.debug("Attempt \(attempt) of \(self.maxRetries)")
                try await operation()
                return
            } catch {
                self.logger.error("Attempt \(attempt) failed: \(error.localizedDescription)")
                lastError = error
                if attempt < self.maxRetries {
                    let delay = UInt64(pow(2.0, Double(attempt)) * 1_000_000_000)
                    self.logger.debug("Retrying in \(delay/1_000_000_000) seconds")
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }
        
        self.logger.error("All retry attempts failed")
        throw TestDataError.firestoreError(lastError ?? NSError(domain: "Unknown", code: 0))
    }
} 