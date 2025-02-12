import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable {
    @DocumentID var id: String?
    let archiveIdentifier: String?
    let userID: String
    let videoURL: String
    let thumbnailURL: String?
    var caption: String
    var description: String?
    var hashtags: [String]
    let createdAt: Date
    var likes: Int
    var views: Int
    var isAdvertisement: Bool?
    
    // Computed property to check if video is from Internet Archive
    var isArchiveVideo: Bool {
        return userID == "archive_user"
    }
    
    // Stable identifier for local use, independent of Firestore document ID
    var stableId: String {
        if isArchiveVideo {
            if let archiveId = archiveIdentifier {
                return "archive_\(archiveId)"
            }
            // For archive videos without an identifier, use the video URL to create a stable ID
            if let urlComponents = URLComponents(string: videoURL),
               let pathComponents = urlComponents.path.components(separatedBy: "/").last {
                return "archive_\(pathComponents)"
            }
        }
        return id ?? UUID().uuidString
    }
    
    // Computed property for display ID
    var displayId: String {
        if userID == "archive_user", let archiveId = archiveIdentifier {
            return archiveId
        }
        return id ?? UUID().uuidString
    }
    
    // Computed property for stats document ID
    var statsDocumentId: String {
        if userID == "archive_user", let archiveId = archiveIdentifier {
            return archiveId
        }
        return stableId
    }
    
    // Make the Identifiable protocol use stableId instead of id
    var identifiableId: String { stableId }
    
    enum CodingKeys: String, CodingKey {
        case id
        case archiveIdentifier
        case userID = "user_id"
        case videoURL = "video_url"
        case thumbnailURL = "thumbnail_url"
        case caption
        case description
        case hashtags
        case createdAt = "created_at"
        case likes
        case views
        case isAdvertisement = "is_advertisement"
    }
    
    init(id: String? = nil,
         archiveIdentifier: String? = nil,
         userID: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         caption: String,
         description: String? = nil,
         hashtags: [String] = [],
         createdAt: Date = Date(),
         likes: Int = 0,
         views: Int = 0,
         isAdvertisement: Bool? = nil) {
        self.id = id
        self.archiveIdentifier = archiveIdentifier
        self.userID = userID
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.caption = caption
        self.description = description
        self.hashtags = hashtags
        self.createdAt = createdAt
        self.likes = likes
        self.views = views
        self.isAdvertisement = isAdvertisement
    }
}