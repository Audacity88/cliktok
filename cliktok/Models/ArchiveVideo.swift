import Foundation

struct ArchiveVideo: Identifiable {
    let id: String
    let identifier: String // Stable identifier for test videos or archive items
    let title: String
    let videoURL: String
    let thumbnailURL: String?
    let description: String?
    
    init(id: String = UUID().uuidString,
         identifier: String? = nil,
         title: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         description: String? = nil) {
        self.id = id
        self.identifier = identifier ?? id // Use id as fallback if no identifier provided
        self.title = title
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.description = description
    }
    
    static let placeholder = ArchiveVideo(
        title: "",
        videoURL: "",
        thumbnailURL: nil,
        description: nil
    )
}
