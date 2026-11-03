import Foundation

struct ArchiveVideo: Identifiable {
    let id: String
    let identifier: String // Stable identifier for test videos or archive items
    let title: String
    let videoURL: String
    let thumbnailURL: String?
    let description: String?
    let creator: String? // Creator or contributor
    let date: String? // Publication or creation date
    let license: String? // License identifier (e.g., "CC0", "Public Domain")
    let archiveURL: String // Link to archive.org page
    
    init(id: String = UUID().uuidString,
         identifier: String? = nil,
         title: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         description: String? = nil,
         creator: String? = nil,
         date: String? = nil,
         license: String? = nil) {
        self.id = id
        self.identifier = identifier ?? id // Use id as fallback if no identifier provided
        self.title = title
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.description = description
        self.creator = creator
        self.date = date
        self.license = license
        self.archiveURL = "https://archive.org/details/\(identifier ?? id)"
    }
    
    static let placeholder = ArchiveVideo(
        title: "",
        videoURL: "",
        thumbnailURL: nil,
        description: nil
    )
}
