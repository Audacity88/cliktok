import Foundation
import AVKit

// Import the ArchiveVideo model
// import Models

struct InternetArchiveMetadata: Codable {
    let metadata: ArchiveMetadata
    let files: [ArchiveFile]
    
    struct ArchiveMetadata: Codable {
        let identifier: String
        let title: String?
        let description: String?
        let mediatype: String?
        let collection: [String]?
    }
    
    struct ArchiveFile: Codable {
        let name: String
        let format: String?
        let title: String?
        let description: String?
        let size: String?
        let source: String?
        let original: String?
        
        // Helper property to identify video files and their priority
        var videoFormat: VideoFormat? {
            let formats: [(String, VideoFormat)] = [
                ("mp4", .mp4),
                ("h.264", .mp4),
                ("mpeg4", .mp4),
                ("m4v", .m4v),
                ("quicktime", .mov),
                ("mov", .mov),
                ("matroska", .mkv)
            ]
            
            // Check format field first
            if let format = format?.lowercased() {
                if let match = formats.first(where: { format.contains($0.0) }) {
                    return match.1
                }
            }
            
            // Check filename extension
            let filename = name.lowercased()
            if filename.hasSuffix(".mp4") { return .mp4 }
            if filename.hasSuffix(".m4v") { return .m4v }
            if filename.hasSuffix(".mov") { return .mov }
            if filename.hasSuffix(".mkv") { return .mkv }
            
            return nil
        }
    }
    
    enum VideoFormat: Int {
        case mp4 = 1  // Highest priority
        case m4v = 2
        case mov = 3
        case mkv = 4  // Lowest priority
        
        var fileExtension: String {
            switch self {
            case .mp4: return "mp4"
            case .m4v: return "m4v"
            case .mov: return "mov"
            case .mkv: return "mkv"
            }
        }
    }
}

struct ArchiveSearchResponse: Codable {
    let response: SearchResponse
    
    struct SearchResponse: Codable {
        let docs: [SearchDoc]
        let numFound: Int
    }
    
    struct SearchDoc: Codable {
        let identifier: String
        let title: String?
        let description: String?
        let mediatype: String?
    }
}

// Static URL generation functions that don't need actor isolation
extension InternetArchiveAPI {
    static let baseURL = "https://archive.org"
    
    static func getVideoURL(identifier: String, filename: String) -> URL {
        let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        return URL(string: "\(baseURL)/download/\(identifier)/\(encodedFilename)")!
    }
    
    static func getThumbnailURL(identifier: String) -> URL {
        URL(string: "\(baseURL)/services/img/\(identifier)")!
    }
}

actor InternetArchiveAPI {
    static let shared = InternetArchiveAPI()
    
    // Cache for metadata to prevent repeated fetches
    private var metadataCache: [String: InternetArchiveMetadata] = [:]
    private var videoCache: [String: [ArchiveVideo]] = [:]
    
    private init() {}
    
    func fetchCollectionItems(identifier: String, offset: Int = 0, limit: Int = 5) async throws -> [ArchiveVideo] {
        print("Searching for items in collection: \(identifier) with offset: \(offset), limit: \(limit)")
        
        // Calculate the page number based on offset and limit
        let page = (offset / limit) + 1
        
        let searchURL = URL(string: "\(Self.baseURL)/advancedsearch.php")!
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)!
        components.queryItems = [
            URLQueryItem(name: "q", value: "collection:\(identifier) AND mediatype:movies"),
            URLQueryItem(name: "fl[]", value: "identifier,title,description,mediatype"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("Search response status code: \(httpResponse.statusCode)")
        }
        
        let searchResponse = try JSONDecoder().decode(ArchiveSearchResponse.self, from: data)
        print("Found \(searchResponse.response.docs.count) items in current page")
        
        var videos: [ArchiveVideo] = []
        
        // Process only the items in the current page
        for doc in searchResponse.response.docs where doc.mediatype == "movies" {
            if let cachedVideos = videoCache[doc.identifier] {
                videos.append(contentsOf: cachedVideos)
                continue
            }
            
            print("Fetching metadata for item: \(doc.identifier)")
            if let metadata = try? await fetchMetadata(identifier: doc.identifier) {
                let itemVideos = getVideoFiles(from: metadata)
                if !itemVideos.isEmpty {
                    videoCache[doc.identifier] = itemVideos
                    videos.append(contentsOf: itemVideos)
                }
            }
        }
        
        print("Total videos found in this page: \(videos.count)")
        return videos
    }
    
    private func fetchMetadata(identifier: String) async throws -> InternetArchiveMetadata {
        // Check cache first
        if let cached = metadataCache[identifier] {
            print("Using cached metadata for \(identifier)")
            return cached
        }
        
        print("Fetching metadata for \(identifier)")
        let url = URL(string: "\(Self.baseURL)/metadata/\(identifier)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let metadata = try JSONDecoder().decode(InternetArchiveMetadata.self, from: data)
        
        // Cache the result
        metadataCache[identifier] = metadata
        return metadata
    }
    
    private func getVideoFiles(from metadata: InternetArchiveMetadata) -> [ArchiveVideo] {
        // First pass: collect all video files and check for MP4 versions
        var videoMap: [String: [(InternetArchiveMetadata.ArchiveFile, InternetArchiveMetadata.VideoFormat)]] = [:]
        
        for file in metadata.files {
            guard let format = file.videoFormat,
                  let size = file.size, !size.isEmpty else { continue }
            
            let baseTitle = file.title ?? metadata.metadata.title ?? file.name
            let key = baseTitle.lowercased()
            
            if videoMap[key] == nil {
                videoMap[key] = []
            }
            videoMap[key]?.append((file, format))
        }
        
        // Second pass: select best format for each video
        var bestFormatVideos: [ArchiveVideo] = []
        
        for (_, variants) in videoMap {
            // Sort variants by format priority
            let sortedVariants = variants.sorted { $0.1.rawValue < $1.1.rawValue }
            
            if let bestVariant = sortedVariants.first {
                let file = bestVariant.0
                let format = bestVariant.1
                
                // Check if an MP4 version exists for the same base name
                let baseName = file.name.replacingOccurrences(of: ".\(format.fileExtension)", with: "")
                let mp4Name = "\(baseName).mp4"
                
                let finalName = metadata.files.contains(where: { $0.name == mp4Name }) ? mp4Name : file.name
                
                let video = ArchiveVideo(
                    title: file.title ?? metadata.metadata.title ?? file.name,
                    videoURL: Self.getVideoURL(identifier: metadata.metadata.identifier, filename: finalName).absoluteString,
                    description: file.description ?? metadata.metadata.description ?? ""
                )
                
                print("Created video: \(video.title) with URL: \(video.videoURL)")
                bestFormatVideos.append(video)
            }
        }
        
        print("Found \(bestFormatVideos.count) videos in \(metadata.metadata.identifier)")
        return bestFormatVideos
    }
    
    private func validateVideoURL(_ urlString: String) async -> Bool {
        guard let url = URL(string: urlString) else { return false }
        
        do {
            let (_, response) = try await URLSession.shared.data(from: url)
            if let httpResponse = response as? HTTPURLResponse {
                return (200...299).contains(httpResponse.statusCode)
            }
            return false
        } catch {
            print("Error validating URL \(urlString): \(error.localizedDescription)")
            return false
        }
    }
    
    func clearCache() {
        metadataCache.removeAll()
        videoCache.removeAll()
    }
}
