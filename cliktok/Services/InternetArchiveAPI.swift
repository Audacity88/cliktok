import Foundation
import AVKit

// Import the ArchiveVideo model
// import Models

struct InternetArchiveMetadata: Codable {
    let metadata: ArchiveMetadata
    let files: [ArchiveFile]  // Changed back to array
    
    struct ArchiveMetadata: Codable {
        let identifier: String
        let title: String?
        let description: String?
        let mediatype: String?
        let collection: [String]?
        
        private enum CodingKeys: String, CodingKey {
            case identifier, title, description, mediatype, collection
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try container.decode(String.self, forKey: .identifier)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            mediatype = try container.decodeIfPresent(String.self, forKey: .mediatype)
            
            // Handle both string and array collection fields
            if let collectionString = try? container.decodeIfPresent(String.self, forKey: .collection) {
                collection = [collectionString]
            } else {
                collection = try container.decodeIfPresent([String].self, forKey: .collection)
            }
        }
    }
    
    struct ArchiveFile: Codable {
        let name: String
        let format: String?
        let title: String?
        let description: String?
        let size: String?
        let source: String?
        let original: String?
        
        private enum CodingKeys: String, CodingKey {
            case name, format, title, description, size, source, original
        }
        
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            name = try container.decode(String.self, forKey: .name)
            format = try container.decodeIfPresent(String.self, forKey: .format)
            title = try container.decodeIfPresent(String.self, forKey: .title)
            description = try container.decodeIfPresent(String.self, forKey: .description)
            size = try container.decodeIfPresent(String.self, forKey: .size)
            source = try container.decodeIfPresent(String.self, forKey: .source)
            original = try container.decodeIfPresent(String.self, forKey: .original)
        }
        
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
    
    static func getVideoURL(identifier: String) -> String {
        // Instead of returning a default URL format, we should try to get the actual URL
        // But since this is a static function, we can't use async/await here
        // So we'll still return the default format, but the caller should use getActualVideoURL instead
        print("Warning: Using default video URL format for \(identifier). Consider using getActualVideoURL instead.")
        return "https://archive.org/download/\(identifier)/\(identifier)_512kb.mp4"
    }
    
    static func getActualVideoURL(identifier: String) async throws -> String {
        // Fetch metadata to get actual file list
        let url = URL(string: "\(baseURL)/metadata/\(identifier)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let metadata = try JSONDecoder().decode(InternetArchiveMetadata.self, from: data)
        
        // Look for video files in order of preference
        let videoFiles = metadata.files.filter { file in
            let name = file.name.lowercased()
            return name.hasSuffix(".mp4") || name.hasSuffix(".m4v") || 
                   name.hasSuffix(".mov") || name.contains("512kb")
        }
        
        // Sort by preference: 512kb.mp4 first, then other mp4s
        let sortedFiles = videoFiles.sorted { file1, file2 in
            let name1 = file1.name.lowercased()
            let name2 = file2.name.lowercased()
            
            // Prefer 512kb versions
            if name1.contains("512kb") && !name2.contains("512kb") {
                return true
            }
            if !name1.contains("512kb") && name2.contains("512kb") {
                return false
            }
            
            // Then prefer mp4
            if name1.hasSuffix(".mp4") && !name2.hasSuffix(".mp4") {
                return true
            }
            if !name1.hasSuffix(".mp4") && name2.hasSuffix(".mp4") {
                return false
            }
            
            // Finally sort by size if available
            if let size1 = Int(file1.size ?? "0"),
               let size2 = Int(file2.size ?? "0") {
                return size1 > size2 // Prefer larger files
            }
            
            return false
        }
        
        // Use the best matching file or fall back to default
        if let bestFile = sortedFiles.first {
            let videoURL = "https://archive.org/download/\(identifier)/\(bestFile.name)"
            print("Found actual video URL: \(videoURL)")
            return videoURL
        }
        
        // If no suitable files found, throw an error instead of using default URL
        throw NSError(domain: "InternetArchive", code: 404, userInfo: [
            NSLocalizedDescriptionKey: "No suitable video file found for identifier: \(identifier)"
        ])
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
    
    func clearCaches() {
        metadataCache.removeAll()
        videoCache.removeAll()
    }
    
    func fetchCollectionItems(identifier: String? = nil, query: String? = nil, offset: Int = 0, limit: Int = 5) async throws -> [ArchiveVideo] {
        print("InternetArchiveAPI: Searching with query: \(query ?? "nil"), collection: \(identifier ?? "nil")")
        
        let searchURL = URL(string: "\(Self.baseURL)/advancedsearch.php")!
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)!
        
        // Build the query string
        let queryString: String
        if let query = query {
            queryString = query
        } else if let identifier = identifier {
            queryString = "collection:\(identifier) AND (mediatype:movies OR mediatype:movingimage)"
        } else {
            queryString = "(mediatype:movies OR mediatype:movingimage)"
        }
        
        // Base query items
        var queryItems = [
            URLQueryItem(name: "q", value: queryString),
            URLQueryItem(name: "fl[]", value: "identifier,title,description,mediatype"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\((offset / limit) + 1)")
        ]
        
        // Add sorting based on query type
        if query != nil {
            // For search queries, sort by relevance and downloads
            queryItems.append(URLQueryItem(name: "sort[]", value: "-downloads"))
            queryItems.append(URLQueryItem(name: "sort[]", value: "-week"))
        } else if identifier == "artsandmusicvideos" {
            queryItems.append(URLQueryItem(name: "sort[]", value: "-reviewdate"))
        } else {
            // Default sorting for collections
            queryItems.append(URLQueryItem(name: "sort[]", value: "-downloads"))
            queryItems.append(URLQueryItem(name: "sort[]", value: "-week"))
        }
        
        components.queryItems = queryItems
        
        let (data, response) = try await URLSession.shared.data(from: components.url!)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("InternetArchiveAPI: Search response status code: \(httpResponse.statusCode)")
            print("InternetArchiveAPI: Search URL: \(components.url?.absoluteString ?? "")")
        }
        
        let searchResponse = try JSONDecoder().decode(ArchiveSearchResponse.self, from: data)
        print("InternetArchiveAPI: Found \(searchResponse.response.docs.count) items in current page")
        
        var videos: [ArchiveVideo] = []
        
        // Process only the items in the current page
        for doc in searchResponse.response.docs {
            if let cachedVideos = videoCache[doc.identifier] {
                print("InternetArchiveAPI: Using cached videos for \(doc.identifier)")
                videos.append(contentsOf: cachedVideos)
                continue
            }
            
            print("InternetArchiveAPI: Fetching metadata for item: \(doc.identifier)")
            if let metadata = try? await fetchMetadata(identifier: doc.identifier) {
                let itemVideos = getVideoFiles(from: metadata)
                if !itemVideos.isEmpty {
                    videoCache[doc.identifier] = itemVideos
                    videos.append(contentsOf: itemVideos)
                    print("InternetArchiveAPI: Added \(itemVideos.count) videos from \(doc.identifier)")
                } else {
                    print("InternetArchiveAPI: No valid videos found in \(doc.identifier)")
                }
            }
        }
        
        print("InternetArchiveAPI: Total videos found in this page: \(videos.count)")
        return videos
    }
    
    private func fetchMetadata(identifier: String) async throws -> InternetArchiveMetadata {
        // Check cache first
        if let cached = metadataCache[identifier] {
            print("InternetArchiveAPI: Using cached metadata for \(identifier)")
            return cached
        }
        
        print("InternetArchiveAPI: Fetching metadata for \(identifier)")
        let url = URL(string: "\(Self.baseURL)/metadata/\(identifier)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            print("InternetArchiveAPI: Metadata response status code: \(httpResponse.statusCode)")
        }
        
        // Print raw JSON for debugging
        if let jsonString = String(data: data, encoding: .utf8) {
            print("InternetArchiveAPI: Raw metadata JSON: \(jsonString.prefix(500))...")
        }
        
        do {
            let metadata = try JSONDecoder().decode(InternetArchiveMetadata.self, from: data)
            print("InternetArchiveAPI: Successfully decoded metadata with \(metadata.files.count) files")
            
            // Print some sample files for debugging
            for file in metadata.files.prefix(5) {
                print("InternetArchiveAPI: Sample file - name: \(file.name), format: \(file.format ?? "nil")")
            }
            
            // Cache the result
            metadataCache[identifier] = metadata
            return metadata
        } catch {
            print("InternetArchiveAPI: Error decoding metadata: \(error)")
            throw error
        }
    }
    
    private func getVideoFiles(from metadata: InternetArchiveMetadata) -> [ArchiveVideo] {
        // First pass: collect all video files and check for MP4 versions
        var videoMap: [String: [(InternetArchiveMetadata.ArchiveFile, InternetArchiveMetadata.VideoFormat)]] = [:]
        
        // Define preferred formats and their priorities
        let preferredFormats = [
            "512kb.mp4": 1,
            ".mp4": 2,
            "h.264": 3,
            "mpeg4": 4,
            "m4v": 5,
            "mov": 6,
            "ogv": 7
        ]
        
        for file in metadata.files {
            // Skip obvious non-video files
            if file.name.hasSuffix(".srt") || file.name.hasSuffix(".vtt") ||
               file.name.hasSuffix(".gif") || file.name.hasSuffix(".jpg") ||
               file.name.hasSuffix(".png") || file.name.hasSuffix(".txt") ||
               file.name.hasSuffix(".nfo") || file.name.hasSuffix(".xml") {
                continue
            }
            
            // Check if this is a video file
            let isVideoFile = preferredFormats.keys.contains { format in
                file.name.lowercased().contains(format.lowercased()) ||
                (file.format?.lowercased().contains(format.lowercased()) ?? false)
            }
            
            if isVideoFile {
                // Get the priority for this format
                let priority = preferredFormats.first { format, _ in
                    file.name.lowercased().contains(format.lowercased()) ||
                    (file.format?.lowercased().contains(format.lowercased()) ?? false)
                }?.value ?? 999
                
                let format = file.videoFormat ?? .mp4
                let baseTitle = file.title ?? metadata.metadata.title ?? file.name
                let key = baseTitle.lowercased()
                
                if videoMap[key] == nil {
                    videoMap[key] = []
                }
                
                videoMap[key]?.append((file, format))
            }
        }
        
        // Second pass: select best format for each video
        var bestFormatVideos: [ArchiveVideo] = []
        
        for (_, variants) in videoMap {
            // Sort variants by format priority and prefer 512kb versions
            let sortedVariants = variants.sorted { (a, b) -> Bool in
                // Always prefer 512kb versions
                if a.0.name.contains("512kb") && !b.0.name.contains("512kb") {
                    return true
                }
                if !a.0.name.contains("512kb") && b.0.name.contains("512kb") {
                    return false
                }
                
                // Then prefer mp4 over other formats
                if a.0.name.hasSuffix(".mp4") && !b.0.name.hasSuffix(".mp4") {
                    return true
                }
                if !a.0.name.hasSuffix(".mp4") && b.0.name.hasSuffix(".mp4") {
                    return false
                }
                
                return a.1.rawValue < b.1.rawValue
            }
            
            if let bestVariant = sortedVariants.first {
                let file = bestVariant.0
                let videoURL = "\(Self.baseURL)/download/\(metadata.metadata.identifier)/\(file.name)"
                
                let video = ArchiveVideo(
                    identifier: metadata.metadata.identifier,
                    title: file.title ?? metadata.metadata.title ?? file.name,
                    videoURL: videoURL,
                    thumbnailURL: Self.getThumbnailURL(identifier: metadata.metadata.identifier).absoluteString,
                    description: file.description ?? metadata.metadata.description ?? ""
                )
                
                bestFormatVideos.append(video)
                print("InternetArchiveAPI: Added video: \(file.name) from \(metadata.metadata.identifier)")
            }
        }
        
        return bestFormatVideos
    }
}
