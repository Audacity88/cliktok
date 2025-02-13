import Foundation
import AVKit

// Remove Models import since ArchiveVideo is in the main target
// Remove Utilities import since Logger is in the main target

// Import the ArchiveVideo model
// import Models  // Remove this comment

// Import ArchiveVideo model and String extension
extension String {
    /// Removes HTML tags and decodes HTML entities from a string
    func cleaningHTMLTags() -> String {
        // Remove HTML tags using regular expressions
        let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive)
        let range = NSRange(location: 0, length: self.utf16.count)
        let cleanedText = regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
        
        // Decode HTML entities and return cleaned text
        return cleanedText?
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? self
    }
}

struct ArchiveVideo {
    let id: String
    let identifier: String
    let title: String
    let videoURL: String
    let thumbnailURL: String?
    let description: String?
    
    init(id: String = UUID().uuidString,
         identifier: String,
         title: String,
         videoURL: String,
         thumbnailURL: String? = nil,
         description: String? = nil) {
        self.id = id
        self.identifier = identifier
        self.title = title
        self.videoURL = videoURL
        self.thumbnailURL = thumbnailURL
        self.description = description
    }
}

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
    
    // Cache for metadata to prevent repeated fetches
    private var metadataCache: [String: InternetArchiveMetadata] = [:]
    private var videoCache: [String: [ArchiveVideo]] = [:]
    private var metadataFetchTasks: [String: Task<InternetArchiveMetadata, Error>] = [:]
    
    private init() {}
    
    func clearCaches() {
        metadataCache.removeAll()
        videoCache.removeAll()
        metadataFetchTasks.values.forEach { $0.cancel() }
        metadataFetchTasks.removeAll()
    }
    
    func fetchCollectionItems(identifier: String? = nil, query: String? = nil, offset: Int = 0, limit: Int = 5) async throws -> [ArchiveVideo] {
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
            // Exclude collections that tend to dominate results
            queryParts.append("-collection:electricsheep")  // Exclude Electric Sheep animations
            queryParts.append("-collection:stream_only")    // Exclude streaming-only content
            queryParts.append("-collection:test_videos")    // Exclude test videos
            queryParts.append("mediatype:movies")          // Only movies
            queryParts.append("format:(mp4 OR h.264)")     // Only common video formats
            
            // Add a random collection filter occasionally
            if Bool.random() {
                let collections = [
                    "prelinger", "classic_tv", "sports", "movie_trailers",
                    "artsandmusicvideos", "newsandpublicaffairs", "opensource_movies",
                    "feature_films", "animation", "vintage_cartoons", "short_films"
                ]
                let randomCollection = collections.randomElement() ?? "prelinger"
                queryParts.append("collection:\(randomCollection)")
            }
        }
        
        // Join query parts with AND
        let queryString = queryParts.joined(separator: " AND ")
        
        // Base query items
        var queryItems = [
            URLQueryItem(name: "q", value: queryString),
            URLQueryItem(name: "output", value: "json"),
            URLQueryItem(name: "rows", value: "\(limit)"),
            URLQueryItem(name: "fl[]", value: "identifier,title,description,mediatype")
        ]
        
        // Add sorting based on query type
        if identifier != nil {
            // Collection-specific: sort by date
            queryItems.append(URLQueryItem(name: "sort[]", value: "addeddate desc"))
        } else if query != nil {
            // Search: sort by relevance and popularity
            queryItems.append(URLQueryItem(name: "sort[]", value: "downloads desc"))
            queryItems.append(URLQueryItem(name: "sort[]", value: "week desc"))
        } else {
            // Random discovery: use random sort with random page
            queryItems.append(URLQueryItem(name: "sort[]", value: "random"))
            queryItems.append(URLQueryItem(name: "seed", value: "\(Int.random(in: 1...999999))"))
            // Use random offset for more variety
            let randomOffset = Int.random(in: 0...200)
            queryItems.append(URLQueryItem(name: "page", value: "\(randomOffset / limit + 1)"))
        }
        
        components.queryItems = queryItems
        
        guard let url = components.url else {
            throw NSError(domain: "InternetArchive", code: 400, userInfo: [
                NSLocalizedDescriptionKey: "Failed to construct valid URL"
            ])
        }
        
        let (data, response) = try await URLSession.shared.data(from: url)
        
        // Debug: Print raw response
        if let jsonString = String(data: data, encoding: .utf8) {
            print("Raw JSON response: \(jsonString)")
        }
        
        if let httpResponse = response as? HTTPURLResponse {
            if httpResponse.statusCode >= 400 {
                if let errorResponse = try? JSONDecoder().decode(ArchiveAPIError.self, from: data) {
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
                var videos: [ArchiveVideo] = []
                
                for doc in searchResponse.response.docs {
                    if let metadata = try? await fetchMetadata(identifier: doc.identifier) {
                        let itemVideos = getVideoFiles(from: metadata)
                        videos.append(contentsOf: itemVideos)
                    }
                }
                
                return videos
                
            } catch {
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
            return cached
        }
        
        // Check if there's already a fetch in progress
        if let existingTask = metadataFetchTasks[identifier] {
            return try await existingTask.value
        }
        
        // Create new fetch task
        let task = Task<InternetArchiveMetadata, Error> {
            let url = URL(string: "\(Self.baseURL)/metadata/\(identifier)")!
            
            let (data, response) = try await URLSession.shared.data(from: url)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Metadata response status: \(httpResponse.statusCode)")
            }
            
            let metadata = try JSONDecoder().decode(InternetArchiveMetadata.self, from: data)
            print("Decoded metadata with \(metadata.files.count) files")
            
            // Cache the result
            metadataCache[identifier] = metadata
            return metadata
        }
        
        // Store the task
        metadataFetchTasks[identifier] = task
        
        do {
            let result = try await task.value
            metadataFetchTasks[identifier] = nil
            return result
        } catch {
            metadataFetchTasks[identifier] = nil
            throw error
        }
    }
    
    private func getVideoFiles(from metadata: InternetArchiveMetadata) -> [ArchiveVideo] {
        // Check video cache first
        if let cached = videoCache[metadata.metadata.identifier] {
            return cached
        }
        
        // Process video files
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
        
        // Filter and process video files
        let videoFiles = metadata.files.filter { file in
            let name = file.name.lowercased()
            let format = file.format?.lowercased() ?? ""
            
            // Skip non-video files early
            if nonVideoExtensions.contains(where: { name.hasSuffix($0) }) {
                return false
            }
            
            return isVideoFile(name: name, format: format)
        }
        
        print("Found \(videoFiles.count) potential video files in \(metadata.metadata.identifier)")
        
        // Group video files by title
        for file in videoFiles {
            if let format = file.videoFormat {
                let baseTitle = file.title ?? metadata.metadata.title ?? file.name
                let key = baseTitle.lowercased()
                videoMap[key, default: []].append((file, format))
            }
        }
        
        // Convert to ArchiveVideo objects
        var bestFormatVideos: [ArchiveVideo] = []
        
        for (_, variants) in videoMap {
            if let bestVariant = selectBestVideoVariant(from: variants) {
                if let video = createArchiveVideo(from: bestVariant.0, metadata: metadata) {
                    bestFormatVideos.append(video)
                }
            }
        }
        
        print("Selected \(bestFormatVideos.count) best format videos from \(metadata.metadata.identifier)")
        
        // Cache the results
        videoCache[metadata.metadata.identifier] = bestFormatVideos
        return bestFormatVideos
    }
    
    // Helper function to check if a file is a video
    private func isVideoFile(name: String, format: String) -> Bool {
        let validVideoExtensions = [".mp4", ".m4v", ".mov", ".avi", ".mkv"]
        let validVideoFormats = ["h.264", "mpeg4", "quicktime", "matroska"]
        
        let isVideoByExtension = validVideoExtensions.contains(where: { name.hasSuffix($0) })
        let isVideoByFormat = validVideoFormats.contains(where: { format.contains($0) })
        let isVideoByFormatField = format.contains("video")
        let is512kbVideo = name.contains("512kb") && validVideoExtensions.contains(where: { name.hasSuffix($0) })
        let isComputerChronicles = name.contains(".cct.") || name.contains("_512kb") || name.contains("_256kb")
        
        return isVideoByExtension || isVideoByFormat || isVideoByFormatField || is512kbVideo || isComputerChronicles
    }
    
    // Helper function to select the best video variant
    private func selectBestVideoVariant(from variants: [(InternetArchiveMetadata.ArchiveFile, InternetArchiveMetadata.VideoFormat)]) -> (InternetArchiveMetadata.ArchiveFile, InternetArchiveMetadata.VideoFormat)? {
        return variants.sorted { (a, b) -> Bool in
            let name1 = a.0.name.lowercased()
            let name2 = b.0.name.lowercased()
            
            // Prefer 512kb versions
            if name1.contains("512kb") && !name2.contains("512kb") { return true }
            if !name1.contains("512kb") && name2.contains("512kb") { return false }
            
            // Then prefer mp4
            if name1.hasSuffix(".mp4") && !name2.hasSuffix(".mp4") { return true }
            if !name1.hasSuffix(".mp4") && name2.hasSuffix(".mp4") { return false }
            
            // Finally sort by size if available
            if let size1 = Int(a.0.size ?? "0"),
               let size2 = Int(b.0.size ?? "0") {
                return size1 > size2 // Prefer larger files
            }
            
            return a.1.rawValue < b.1.rawValue
        }.first
    }
    
    // Helper function to create ArchiveVideo object
    private func createArchiveVideo(from file: InternetArchiveMetadata.ArchiveFile, metadata: InternetArchiveMetadata) -> ArchiveVideo? {
        let videoURL = "\(Self.baseURL)/download/\(metadata.metadata.identifier)/\(file.name)"
        
        return ArchiveVideo(
            identifier: metadata.metadata.identifier,
            title: (file.title ?? metadata.metadata.title ?? file.name).cleaningHTMLTags(),
            videoURL: videoURL,
            thumbnailURL: Self.getThumbnailURL(identifier: metadata.metadata.identifier).absoluteString,
            description: (file.description ?? metadata.metadata.description ?? "").cleaningHTMLTags()
        )
    }
}

