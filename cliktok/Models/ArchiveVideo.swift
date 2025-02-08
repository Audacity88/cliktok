import Foundation

struct ArchiveVideo: Identifiable {
    let id: String
    let title: String
    let videoURL: String
    let thumbnailURL: String?
    let description: String?
    
    init(id: String = UUID().uuidString,
         title: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         description: String? = nil) {
        self.id = id
        self.title = title
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.description = description
    }
}
