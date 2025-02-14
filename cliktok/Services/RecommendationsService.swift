import Foundation
import FirebaseFirestore
import OpenAI

actor RecommendationsService {
    static let shared = RecommendationsService()
    private let db = Firestore.firestore()
    private let aiSearchService = AISearchService.shared
    private var client: OpenAI?
    
    private init() {}
    
    struct RecommendationSummary {
        let interests: [String]
        let topCategories: [String]
        let recommendedVideos: [Video]
        let tippedVideos: [Video]
        let explanation: String
    }
    
    func generateRecommendations(from tips: [Tip]) async throws -> RecommendationSummary {
        // Get videos from tips
        var tippedVideos: [Video] = []
        for tip in tips {
            if tip.videoID.hasPrefix("archive_") {
                let archiveId = String(tip.videoID.dropFirst(8))
                let video = Video(
                    id: nil,
                    archiveIdentifier: archiveId,
                    userID: "archive_user",
                    videoURL: InternetArchiveAPI.getVideoURL(identifier: archiveId),
                    thumbnailURL: InternetArchiveAPI.getThumbnailURL(identifier: archiveId).absoluteString,
                    caption: "Archive Video",
                    description: nil,
                    hashtags: ["archive"],
                    createdAt: tip.timestamp,
                    likes: 0,
                    views: 0
                )
                tippedVideos.append(video)
            } else {
                do {
                    let doc = try await db.collection("videos").document(tip.videoID).getDocument()
                    if let video = try? doc.data(as: Video.self) {
                        tippedVideos.append(video)
                    }
                } catch {
                    print("Error fetching video \(tip.videoID): \(error)")
                }
            }
        }
        
        // Combine video metadata for analysis
        let tippedContent = tippedVideos.map { video in
            let tipAmount = tips.first(where: { $0.videoID == video.id })?.amount ?? 0
            return """
            Video: \(video.caption)
            Description: \(video.description ?? "")
            Hashtags: \(video.hashtags.joined(separator: ", "))
            Amount: $\(String(format: "%.2f", tipAmount))
            """
        }.joined(separator: "\n\n")
        
        // Get OpenAI client
        if client == nil {
            let apiKey = try Configuration.openAIApiKey
            client = OpenAI(apiToken: apiKey)
        }
        
        guard let client = client else {
            throw AISearchError.invalidAPIKey
        }
        
        // Generate AI analysis
        let systemPrompt = """
        You are a video recommendation expert. Analyze these tipped videos, considering tip amounts as indicators of user preference strength.
        Extract:
        1. Main interests (comma-separated), ordered by strength of preference
        2. Top 3 content categories, ordered by relevance
        3. Brief explanation of the user's preferences, mentioning their strongest interests
        
        Return in this exact format:
        INTERESTS: interest1, interest2, interest3
        CATEGORIES: category1, category2, category3
        EXPLANATION: Your explanation here
        """
        
        let userContent = """
        Analyze these tipped videos:
        \(tippedContent)
        """
        
        let messages: [ChatQuery.ChatCompletionMessageParam] = [
            try .init(role: .system, content: systemPrompt)!,
            try .init(role: .user, content: userContent)!
        ]
        
        let query = ChatQuery(messages: messages, model: .gpt4_turbo_preview)
        let result = try await client.chats(query: query)
        
        guard case let .string(content) = result.choices.first?.message.content else {
            throw AISearchError.processingFailed
        }
        
        // Parse the AI response
        var interests: [String] = []
        var categories: [String] = []
        var explanation = ""
        
        let lines = content.components(separatedBy: "\n")
        for line in lines {
            if line.starts(with: "INTERESTS:") {
                interests = line.replacingOccurrences(of: "INTERESTS:", with: "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else if line.starts(with: "CATEGORIES:") {
                categories = line.replacingOccurrences(of: "CATEGORIES:", with: "")
                    .components(separatedBy: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty }
            } else if line.starts(with: "EXPLANATION:") {
                explanation = line.replacingOccurrences(of: "EXPLANATION:", with: "").trimmingCharacters(in: .whitespaces)
            }
        }
        
        // Find similar videos
        let taskId = await aiSearchService.startTask()
        
        do {
            // Get the top 3 interests for focused search
            let primaryInterests = interests.prefix(3)
            
            // Map interests to relevant collections
            let collectionMapping: [String: [String]] = [
                "music": ["artsandmusicvideos", "opensource_music"],
                "film": ["feature_films", "movie_trailers", "short_films"],
                "education": ["prelinger", "educational_films"],
                "sports": ["sports"],
                "gaming": ["opensource_movies", "classic_tv"],
                "art": ["artsandmusicvideos", "animation"],
                "technology": ["opensource_movies", "educational_films"],
                "history": ["prelinger", "classic_tv"],
                "entertainment": ["classic_tv", "feature_films"],
                "news": ["newsandpublicaffairs"]
            ]
            
            // Build collection filter based on interests
            var targetCollections = Set<String>()
            for interest in primaryInterests {
                let interestKey = interest.lowercased()
                for (key, collections) in collectionMapping {
                    if interestKey.contains(key) {
                        targetCollections.formUnion(collections)
                    }
                }
            }
            
            // Default collections if no matches
            if targetCollections.isEmpty {
                targetCollections = ["opensource_movies", "artsandmusicvideos", "classic_tv"]
            }
            
            // Construct a more focused search query
            let searchTerms = primaryInterests.map { "(\($0))" }.joined(separator: " AND ")
            let categoryTerms = categories.prefix(2).map { "(\($0))" }.joined(separator: " AND ")
            let collectionFilter = targetCollections.map { "collection:\($0)" }.joined(separator: " OR ")
            
            let searchQuery = """
                (\(searchTerms)) AND (\(categoryTerms))
                AND (mediatype:movies OR mediatype:video)
                AND -collection:test_collection AND -collection:samples
                AND (\(collectionFilter))
            """
            
            // Search across targeted collections in parallel
            var collectionResults: [[ArchiveVideo]] = []
            for collection in targetCollections {
                async let items = InternetArchiveAPI.shared.fetchCollectionItems(
                    identifier: collection,
                    offset: 0,
                    limit: 5
                )
                collectionResults.append(try await items)
            }
            
            // Combine and rank all results
            let allVideos = try await collectionResults.flatMap { $0 }
            let rankedVideos = try await aiSearchService.searchAndRankVideos(allVideos, query: searchQuery, taskId: taskId)
            
            // Take top 10 most relevant videos
            let topVideos = Array(rankedVideos.prefix(10))
            
            // Convert ArchiveVideo to Video with better metadata
            let recommendedVideos = topVideos.map { archiveVideo in
                // Extract year from title if available
                let yearPattern = /\((\d{4})\)/
                let year = archiveVideo.title.firstMatch(of: yearPattern)?.1 ?? ""
                
                // Clean up the title
                var cleanTitle = archiveVideo.title
                    .replacingOccurrences(of: "\\([^)]+\\)", with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
                if !year.isEmpty {
                    cleanTitle += " (\(year))"
                }
                
                return Video(
                    id: "rec_\(archiveVideo.identifier)",
                    archiveIdentifier: archiveVideo.identifier,
                    userID: "archive_user",
                    videoURL: InternetArchiveAPI.getVideoURL(identifier: archiveVideo.identifier),
                    thumbnailURL: InternetArchiveAPI.getThumbnailURL(identifier: archiveVideo.identifier).absoluteString,
                    caption: cleanTitle,
                    description: archiveVideo.description,
                    hashtags: categories, // Use the AI-generated categories as hashtags
                    createdAt: Date(),
                    likes: 0,
                    views: 0
                )
            }
            
            // Use the non-isolated method to handle task cancellation
            aiSearchService.handleTaskCancellation(taskId)
            
            return RecommendationSummary(
                interests: interests,
                topCategories: categories,
                recommendedVideos: recommendedVideos,
                tippedVideos: tippedVideos,
                explanation: explanation
            )
        } catch {
            // Make sure to cancel the task even if an error occurs
            aiSearchService.handleTaskCancellation(taskId)
            throw error
        }
    }
} 