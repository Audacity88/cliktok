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
    let responseHeader: ResponseHeader
    let response: SearchResponse
    
    struct ResponseHeader: Codable {
        let status: Int
        let QTime: Int
        let params: SearchParams
        
        struct SearchParams: Codable {
            let query: String
            let qin: String
            let fields: String
            let wt: String
            let sort: String?
            let rows: String
            let start: Int
            
            private enum CodingKeys: String, CodingKey {
                case query, qin, fields = "fields", wt, sort, rows, start
            }
        }
    }
    
    struct SearchResponse: Codable {
        let docs: [SearchDoc]
        let numFound: Int
        let start: Int
    }
    
    struct SearchDoc: Codable {
        let identifier: String
        let title: String?
        let description: String?
        let mediatype: String?
    }
}

// Add error response structure
struct ArchiveAPIError: Codable {
    let error: String
    let forensics: Forensics
    
    struct Forensics: Codable {
        let timestamp: String
        let message: String
        let statusCode: Int
        
        private enum CodingKeys: String, CodingKey {
            case timestamp
            case message
            case statusCode = "status_code"
        }
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
        
        // Known video extensions and formats
        let validVideoExtensions = [".mp4", ".m4v", ".mov", ".avi", ".mkv"]
        let validVideoFormats = ["h.264", "mpeg4", "quicktime", "matroska"]
        
        // Look for video files in order of preference
        let videoFiles = metadata.files.filter { file in
            let name = file.name.lowercased()
            let format = file.format?.lowercased() ?? ""
            
            // First check if it's a known non-video file
            let nonVideoExtensions = [
                ".mp3", ".ogg", ".wav", ".m4a", ".aac",  // Audio
                ".srt", ".vtt",                          // Subtitles
                ".gif", ".jpg", ".jpeg", ".png",         // Images
                ".txt", ".nfo", ".xml", ".json",         // Text/Data
                ".pdf", ".doc", ".docx",                 // Documents
                ".sqlite", ".db", ".meta",               // Database/metadata
                ".afpk", ".pkg",                         // Package files
                ".zip", ".rar", ".7z"                    // Archives
            ]
            
            if nonVideoExtensions.contains(where: { name.hasSuffix($0) }) {
                return false
            }
            
            // Then check if it's explicitly a video file
            let isVideoByExtension = validVideoExtensions.contains(where: { name.hasSuffix($0) })
            let isVideoByFormat = validVideoFormats.contains(where: { format.contains($0) })
            let isVideoByFormatField = format.contains("video")
            let is512kbVideo = name.contains("512kb") && validVideoExtensions.contains(where: { name.hasSuffix($0) })
            let isComputerChronicles = name.contains(".cct.") || name.contains("_512kb") || name.contains("_256kb")
            
            return isVideoByExtension || isVideoByFormat || isVideoByFormatField || is512kbVideo || isComputerChronicles
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
            return videoURL
        }
        
        // If no suitable files found, throw an error with more context
        let mediaType = metadata.metadata.mediatype ?? "unknown"
        let errorMessage = "No suitable video file found for identifier: \(identifier) (Media Type: \(mediaType))"
        throw NSError(domain: "InternetArchive", code: 404, userInfo: [
            NSLocalizedDescriptionKey: errorMessage
        ])
    }
    
    static func getThumbnailURL(identifier: String) -> URL {
        URL(string: "\(baseURL)/services/img/\(identifier)")!
    }
}

actor InternetArchiveAPI {
    static let shared = InternetArchiveAPI()
    private let logger = Logger(component: "InternetArchiveAPI")
    
    // Cache for metadata to prevent repeated fetches
    private var metadataCache: [String: InternetArchiveMetadata] = [:]
    private var videoCache: [String: [ArchiveVideo]] = [:]
    
    private init() {}
    
    func clearCaches() {
        metadataCache.removeAll()
        videoCache.removeAll()
        logger.info("Caches cleared")
    }
    
    func fetchCollectionItems(identifier: String? = nil, query: String? = nil, offset: Int = 0, limit: Int = 5) async throws -> [ArchiveVideo] {
        logger.debug("Fetching items - Query: \(query ?? "nil"), Collection: \(identifier ?? "nil")")
        
        let searchURL = URL(string: "\(Self.baseURL)/advancedsearch.php")!
        var components = URLComponents(url: searchURL, resolvingAgainstBaseURL: true)!
        
        // Build the query string without parentheses or special characters
        var queryParts: [String] = []
        
        if let identifier = identifier {
            // For collection-specific searches
            queryParts.append("collection:\(identifier)")
            queryParts.append("mediatype:movies")
        } else if let query = query {
            // For search/trending queries
            queryParts.append(query)
            queryParts.append("mediatype:movies")
        } else {
            // For random discovery
            let collections = ["prelinger", "classic_tv", "sports", "movie_trailers", "artsandmusicvideos", "newsandpublicaffairs", "opensource_movies"]
            let randomCollection = collections.randomElement() ?? "prelinger"
            queryParts.append("collection:\(randomCollection)")
            queryParts.append("mediatype:movies")
        }
        
        // Join query parts with AND
        let queryString = queryParts.joined(separator: " AND ")
        
        // Base query items
        var queryItems = [
            URLQueryItem(name: "q", value: queryString),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "\(limit)"),
            URLQueryItem(name: "page", value: "\(offset / limit + 1)"),
            URLQueryItem(name: "fl[]", value: "identifier,title,description,mediatype")
        ]
        
        // Add sorting based on query type
        if identifier != nil {
            queryItems.append(URLQueryItem(name: "sort[]", value: "addeddate desc"))
        } else if query != nil {
            queryItems.append(URLQueryItem(name: "sort[]", value: "downloads desc"))
        } else {
            queryItems.append(URLQueryItem(name: "sort[]", value: "random"))
            queryItems.append(URLQueryItem(name: "seed", value: "\(Int.random(in: 1...999999))"))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            logger.error("Failed to construct URL from components")
            throw NSError(domain: "InternetArchive", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Failed to construct valid URL"
            ])
        }
        
        logger.debug("Fetching from URL: \(url.absoluteString)")
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Debug: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw JSON response: \(jsonString)")
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Search response status: \(httpResponse.statusCode)")
            
            // Check for error response first
            if httpResponse.statusCode >= 400 {
                if let errorResponse = try? JSONDecoder().decode(ArchiveAPIError.self, from: data) {
                    logger.error("API Error: \(errorResponse.error)")
                    throw NSError(domain: "InternetArchive", code: httpResponse.statusCode, userInfo: [
                        NSLocalizedDescriptionKey: errorResponse.error
                    ])
                }
                throw NSError(domain: "InternetArchive", code: httpResponse.statusCode, userInfo: [
                    NSLocalizedDescriptionKey: "API request failed"
                ])
            }
            
            // Try to decode the successful response
            do {
                let searchResponse = try JSONDecoder().decode(ArchiveSearchResponse.self, from: data)
                logger.info("Found \(searchResponse.response.docs.count) items")
                
                var videos: [ArchiveVideo] = []
                
                for doc in searchResponse.response.docs {
                    if let metadata = try? await fetchMetadata(identifier: doc.identifier) {
                        let itemVideos = getVideoFiles(from: metadata)
                        videos.append(contentsOf: itemVideos)
                    }
                }
                
                return videos
                
            } catch {
                logger.error("Error decoding response: \(error)")
                throw error
            }
        }
        
        throw NSError(domain: "InternetArchive", code: 500, userInfo: [
            NSLocalizedDescriptionKey: "Invalid response from server"
        ])
    }
    
    private func fetchMetadata(identifier: String) async throws -> InternetArchiveMetadata {
        // Check cache first
        if let cached = metadataCache[identifier] {
            logger.debug("Using cached metadata for \(identifier)")
            return cached
        }
        
        logger.debug("Fetching metadata for \(identifier)")
        let url = URL(string: "\(Self.baseURL)/metadata/\(identifier)")!
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        if let httpResponse = response as? HTTPURLResponse {
            logger.debug("Metadata response status: \(httpResponse.statusCode)")
        }
        
        do {
            let metadata = try JSONDecoder().decode(InternetArchiveMetadata.self, from: data)
            logger.debug("Decoded metadata with \(metadata.files.count) files")
            
            // Cache the result
            metadataCache[identifier] = metadata
            return metadata
        } catch {
            logger.error("Error decoding metadata: \(error)")
            throw error
        }
    }
    
    private func getVideoFiles(from metadata: InternetArchiveMetadata) -> [ArchiveVideo] {
        var videoMap: [String: [(InternetArchiveMetadata.ArchiveFile, InternetArchiveMetadata.VideoFormat)]] = [:]
        
        // Known video extensions and formats
        let validVideoExtensions = [".mp4", ".m4v", ".mov", ".avi", ".mkv"]
        let validVideoFormats = ["h.264", "mpeg4", "quicktime", "matroska"]
        
        // Known non-video extensions
        let nonVideoExtensions = [
            ".mp3", ".ogg", ".wav", ".m4a", ".aac",  // Audio
            ".srt", ".vtt",                          // Subtitles
            ".gif", ".jpg", ".jpeg", ".png",         // Images
            ".txt", ".nfo", ".xml", ".json",         // Text/Data
            ".pdf", ".doc", ".docx",                 // Documents
            ".sqlite", ".db", ".meta",               // Database/metadata
            ".afpk", ".pkg",                         // Package files
            ".zip", ".rar", ".7z"                    // Archives
        ]
        
        for file in metadata.files {
            let name = file.name.lowercased()
            let format = file.format?.lowercased() ?? ""
            
            // Skip files with known non-video extensions
            if nonVideoExtensions.contains(where: { name.hasSuffix($0) }) {
                continue
            }
            
            // Check if this is a video file using multiple criteria
            let isVideoByExtension = validVideoExtensions.contains(where: { name.hasSuffix($0) })
            let isVideoByFormat = validVideoFormats.contains(where: { format.contains($0) })
            let isVideoByFormatField = format.contains("video")
            let is512kbVideo = name.contains("512kb") && validVideoExtensions.contains(where: { name.hasSuffix($0) })
            let isComputerChronicles = name.contains(".cct.") || name.contains("_512kb") || name.contains("_256kb")
            
            let isVideoFile = isVideoByExtension || isVideoByFormat || isVideoByFormatField || is512kbVideo || isComputerChronicles
            
            if isVideoFile {
                let format = file.videoFormat ?? .mp4
                let baseTitle = file.title ?? metadata.metadata.title ?? file.name
                let key = baseTitle.lowercased()
                
                if videoMap[key] == nil {
                    videoMap[key] = []
                }
                
                videoMap[key]?.append((file, format))
            }
        }
        
        // If no video files found, return empty array
        if videoMap.isEmpty {
            return []
        }
        
        var bestFormatVideos: [ArchiveVideo] = []
        
        for (_, variants) in videoMap {
            let sortedVariants = variants.sorted { (a, b) -> Bool in
                let name1 = a.0.name.lowercased()
                let name2 = b.0.name.lowercased()
                
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
                if let size1 = Int(a.0.size ?? "0"),
                   let size2 = Int(b.0.size ?? "0") {
                    return size1 > size2 // Prefer larger files
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
            }
        }
        
        return bestFormatVideos
    }
}

