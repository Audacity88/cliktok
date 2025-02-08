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
    
    static func getVideoURL(identifier: String, filename: String) -> URL {
        // First try to get a direct download URL
        let encodedFilename = filename.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? filename
        let directURL = URL(string: "\(baseURL)/download/\(identifier)/\(encodedFilename)")!
        
        // For certain formats, try to get an alternative streaming URL
        if filename.hasSuffix(".m4v") {
            // Try mp4 version first
            let mp4Filename = filename.replacingOccurrences(of: ".m4v", with: ".mp4")
            return URL(string: "\(baseURL)/download/\(identifier)/\(mp4Filename)")!
        }
        
        // For older formats, try to get the streaming version
        if filename.hasSuffix(".avi") || filename.hasSuffix(".rm") || filename.hasSuffix(".wmv") {
            // Look for _512kb.mp4 version
            let streamingFilename = filename.replacingOccurrences(
                of: #"\.(?:avi|rm|wmv)$"#,
                with: "_512kb.mp4",
                options: .regularExpression
            )
            return URL(string: "\(baseURL)/download/\(identifier)/\(streamingFilename)")!
        }
        
        // Try alternative URL formats for problematic files
        if filename.hasSuffix(".mp4") {
            // Try with _512kb suffix first
            let streamingFilename = filename.replacingOccurrences(of: ".mp4", with: "_512kb.mp4")
            let streamingURL = URL(string: "\(baseURL)/download/\(identifier)/\(streamingFilename)")!
            
            // Try with h264 suffix as fallback
            let h264Filename = filename.replacingOccurrences(of: ".mp4", with: "_h264.mp4")
            let h264URL = URL(string: "\(baseURL)/download/\(identifier)/\(h264Filename)")!
            
            // Try with original filename but different path format
            let altURL = URL(string: "\(baseURL)/serve/\(identifier)/\(encodedFilename)")
            
            // Return the first valid URL
            if let altURL = altURL {
                return altURL
            }
            
            // Default to streaming version if available
            return streamingURL
        }
        
        return directURL
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
        print("InternetArchiveAPI: Searching for items in collection: \(identifier) with offset: \(offset), limit: \(limit)")
        
        // Calculate the page number based on offset and limit
        let page = (offset / limit) + 1
        
        let searchURL = URL(string: "\(Self.baseURL)/advancedsearch.php")!
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)!
        
        // Base query items
        var queryItems = [
            URLQueryItem(name: "q", value: "collection:\(identifier) AND (mediatype:movies OR mediatype:movingimage)"),
            URLQueryItem(name: "fl[]", value: "identifier,title,description,mediatype"),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\(page)")
        ]
        
        // Add collection-specific sorting
        if identifier == "artsandmusicvideos" {
            queryItems.append(URLQueryItem(name: "sort[]", value: "-reviewdate"))
        } else {
            // Default sorting for other collections
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
        print("InternetArchiveAPI: Processing files for \(metadata.metadata.identifier)")
        print("InternetArchiveAPI: Total files found: \(metadata.files.count)")
        
        // First pass: collect all video files and check for MP4 versions
        var videoMap: [String: [(InternetArchiveMetadata.ArchiveFile, InternetArchiveMetadata.VideoFormat)]] = [:]
        
        // Define preferred formats and their priorities
        let preferredFormats = [
            "512kb.mp4": 1,
            "mp4": 2,
            "h.264": 3,
            "mpeg4": 4,
            "m4v": 5,
            "mov": 6,
            "ogv": 7
        ]
        
        for file in metadata.files {
            // Debug print file info
            print("InternetArchiveAPI: Checking file: \(file.name), format: \(file.format ?? "nil")")
            
            // Skip files that are clearly derivatives or thumbnails
            if file.name.contains("_thumb") || file.name.contains("_small") || 
               file.name.contains("_preview") || file.name.contains(".gif") ||
               file.name.contains("_pixels") || file.name.contains(".rm") ||
               file.name.contains("_meta") || file.name.contains(".srt") ||
               file.name.contains(".vtt") || file.name.contains("_reviews") ||
               file.name.contains("_archive") || file.name.contains("_files") ||
               file.name.contains("_meta.xml") || file.name.contains(".sqlite") ||
               file.name.contains(".torrent") || file.name.contains("__ia_thumb") {
                print("InternetArchiveAPI: Skipping derivative file: \(file.name)")
                continue
            }
            
            // Skip very small files (likely thumbnails or previews)
            if let size = file.size, let sizeInt = Int(size), sizeInt < 1000000 {
                print("InternetArchiveAPI: Skipping small file: \(file.name) (\(size) bytes)")
                continue
            }
            
            // Skip files marked as derivatives
            if file.source?.lowercased() == "derivative" {
                print("InternetArchiveAPI: Skipping derivative source file: \(file.name)")
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
                print("InternetArchiveAPI: Added video file: \(file.name) with priority \(priority)")
            }
        }
        
        print("InternetArchiveAPI: Found \(videoMap.count) potential videos")
        
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
                let videoURL = Self.getVideoURL(identifier: metadata.metadata.identifier, filename: file.name).absoluteString
                
                let video = ArchiveVideo(
                    title: file.title ?? metadata.metadata.title ?? file.name,
                    videoURL: videoURL,
                    description: file.description ?? metadata.metadata.description ?? ""
                )
                
                print("InternetArchiveAPI: Created video: \(video.title) with URL: \(video.videoURL)")
                bestFormatVideos.append(video)
            }
        }
        
        print("InternetArchiveAPI: Found \(bestFormatVideos.count) videos in \(metadata.metadata.identifier)")
        return bestFormatVideos
    }
    
    func clearCache() {
        metadataCache.removeAll()
        videoCache.removeAll()
    }
}
