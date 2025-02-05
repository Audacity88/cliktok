import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable {
    @DocumentID var id: String?
    let userID: String
    let videoURL: String
    let thumbnailURL: String?
    let caption: String
    let hashtags: [String]
    let createdAt: Date
    var likes: Int
    var views: Int
    
    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case videoURL = "video_url"
        case thumbnailURL = "thumbnail_url"
        case caption
        case hashtags
        case createdAt = "created_at"
        case likes
        case views
    }
} 