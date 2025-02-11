import Foundation
import FirebaseFirestore

struct ArchiveVideo: Identifiable, Codable {
    @DocumentID var id: String?
    let archiveIdentifier: String
    let title: String
    let videoURL: String
    let thumbnailURL: String?
    let description: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case archiveIdentifier
        case title
        case videoURL
        case thumbnailURL
        case description
    }
    
    init(id: String? = nil,
         archiveIdentifier: String,
         title: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         description: String? = nil) {
        self.id = id
        self.archiveIdentifier = archiveIdentifier
        self.title = title
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.description = description
    }
    
    static let placeholder = ArchiveVideo(
        archiveIdentifier: "",
        title: "",
        videoURL: "",
        thumbnailURL: nil,
        description: nil
    )
}
