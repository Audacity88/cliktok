import Foundation

struct ArchiveCollection: Identifiable, Equatable {
    let id: String
    let title: String
    let description: String
    let thumbnailURL: String?
    var videos: [ArchiveVideo]
    
    init(id: String, title: String, description: String, thumbnailURL: String? = nil, videos: [ArchiveVideo] = []) {
        self.id = id
        self.title = title
        self.description = description
        self.thumbnailURL = thumbnailURL
        self.videos = videos
    }
    
    static func == (lhs: ArchiveCollection, rhs: ArchiveCollection) -> Bool {
        lhs.id == rhs.id
    }
}
