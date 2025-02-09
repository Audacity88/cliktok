import Foundation
import FirebaseFirestore

struct Video: Identifiable, Codable {
    @DocumentID var id: String?
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
    
    enum CodingKeys: String, CodingKey {
        case id
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
         userID: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         caption: String,
         description: String? = nil,
         hashtags: [String],
         createdAt: Date = Date(),
         likes: Int = 0,
         views: Int = 0,
         isAdvertisement: Bool? = nil) {
        self.id = id
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