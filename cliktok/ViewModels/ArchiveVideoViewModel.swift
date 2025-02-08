import Foundation
import SwiftUI

class ArchiveVideoViewModel: ObservableObject {
    @Published var collections: [ArchiveCollection] = []
    @Published var selectedCollection: ArchiveCollection?
    @Published var isLoading = false
    @Published var error: String?
    
    init() {
        // Add initial collections
        addTestCollections()
    }
    
    private func addTestCollections() {
        // Test Videos Collection
        let testVideos = ArchiveCollection(
            id: "test_videos",
            title: "Test Videos",
            description: "Sample videos for testing",
            videos: [
                ArchiveVideo(
                    title: "Test Pattern",
                    videoURL: "https://commondatastorage.googleapis.com/gtv-videos-bucket/sample/ForBiggerBlazes.mp4",
                    description: "Test video for streaming"
                ),
                ArchiveVideo(
                    title: "Big Buck Bunny",
                    videoURL: "https://archive.org/download/BigBuckBunny_328/BigBuckBunny_512kb.mp4",
                    description: "Big Buck Bunny - Classic open source animation"
                ),
                ArchiveVideo(
                    title: "Elephants Dream",
                    videoURL: "https://archive.org/download/ElephantsDream/ed_1024_512kb.mp4",
                    description: "Elephants Dream - First Blender Open Movie"
                )
            ]
        )
        
        // Demolition Kitchen Collection
        let demolitionKitchen = ArchiveCollection(
            id: "demolitionkitchenvideo",
            title: "Demolition Kitchen",
            description: "Videos from the Demolition Kitchen collection",
            thumbnailURL: "https://archive.org/services/img/demolitionkitchenvideo"
        )
        
        collections = [testVideos, demolitionKitchen]
        selectedCollection = testVideos
    }
    
    func loadCollectionVideos(for collection: ArchiveCollection) async {
        guard collection.id == "demolitionkitchenvideo" else { return }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            // TODO: Implement proper Internet Archive API
            // For now, adding some sample videos from the collection
            var updatedCollection = collection
            updatedCollection.videos = [
                ArchiveVideo(
                    title: "Demolition Kitchen - Episode 1",
                    videoURL: "https://archive.org/download/demolitionkitchenvideo/Demolition%20Kitchen%20-%20Episode%201.mp4",
                    description: "First episode of Demolition Kitchen"
                ),
                ArchiveVideo(
                    title: "Demolition Kitchen - Episode 2",
                    videoURL: "https://archive.org/download/demolitionkitchenvideo/Demolition%20Kitchen%20-%20Episode%202.mp4",
                    description: "Second episode of Demolition Kitchen"
                )
            ]
            
            if let index = collections.firstIndex(where: { $0.id == collection.id }) {
                collections[index] = updatedCollection
                if selectedCollection?.id == collection.id {
                    selectedCollection = updatedCollection
                }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }
}
