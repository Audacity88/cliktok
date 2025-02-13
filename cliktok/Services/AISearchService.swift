import Foundation
import OpenAI
import Combine
import os

enum AISearchError: Error {
    case invalidAPIKey
    case processingFailed
    case rankingFailed
    case cancelled
    case unknown(Error)
    
    var localizedDescription: String {
        switch self {
        case .invalidAPIKey:
            return "OpenAI API key not configured. Please check your environment variables."
        case .processingFailed:
            return "Failed to process search query. Please check your OpenAI API key configuration."
        case .rankingFailed:
            return "Failed to rank search results. Please try again."
        case .cancelled:
            return "Search cancelled."
        case .unknown(let error):
            return "An unexpected error occurred: \(error.localizedDescription)"
        }
    }
}

actor AISearchService {
    private var client: OpenAI?
    static let shared = AISearchService()
    private var activeTasks: Set<UUID> = []
    private let logger = Logger(component: "AISearchService")
    
    // Constants
    static let MAX_SEARCH_RESULTS = 10
    static let MAX_TOKENS = 128000
    
    private init() {}
    
    private func getClient() throws -> OpenAI {
        if let client = client {
            return client
        }
        
        let apiKey: String
        do {
            apiKey = try Configuration.openAIApiKey
        } catch {
            #if DEBUG
            print("""
            ⚠️ OpenAI API key not found!
            
            Please set up the OPENAI_API_KEY environment variable:
            1. Open Xcode
            2. Select cliktok scheme
            3. Edit Scheme...
            4. Run > Arguments > Environment Variables
            5. Add OPENAI_API_KEY with your API key
            """)
            #endif
            throw AISearchError.invalidAPIKey
        }
        
        let newClient = OpenAI(apiToken: apiKey)
        client = newClient
        return newClient
    }
    
    /// Search and rank videos using GPT-3.5
    func searchAndRankVideos(_ videos: [ArchiveVideo], query: String, taskId: UUID) async throws -> [ArchiveVideo] {
        guard activeTasks.contains(taskId) else { throw AISearchError.cancelled }
        guard !videos.isEmpty else { return videos }
        
        logger.info("Starting ranking for \(videos.count) videos with query: \(query)")
        let client = try getClient()
        
        // Use GPT-3.5 for faster ranking
        let systemPrompt = """
        You are a video search expert. Rate each video's relevance to the query from 0-100.
        Consider these factors:
        1. Title and description match to query terms
        2. Overall content relevance
        3. Video quality indicators
        4. Potential user engagement
        
        Return ONLY comma-separated numbers from 0-100 (e.g. "90,45,20"). 
        No other text or explanation.
        Higher numbers mean more relevant.
        """
        
        // Process videos in smaller batches to stay within token limits
        let BATCH_SIZE = 25  // Increased from 8 to 25 since we have more context window
        let videosToRank = Array(videos.prefix(AISearchService.MAX_SEARCH_RESULTS))
        var allRankedVideos: [(video: ArchiveVideo, score: Double)] = []
        
        // Process each batch
        for batchStart in stride(from: 0, to: videosToRank.count, by: BATCH_SIZE) {
            let batchEnd = min(batchStart + BATCH_SIZE, videosToRank.count)
            let batch = Array(videosToRank[batchStart..<batchEnd])
            
            logger.info("Processing batch \(batchStart/BATCH_SIZE + 1) with \(batch.count) videos")
            
            let batchInfo = batch.enumerated().map { index, video in
                """
                [\(index + 1)]
                Title: \(video.title)
                Description: \(video.description?.cleaningHTMLTags() ?? "No description")
                ---
                """
            }.joined(separator: "\n")
            
            let userContent = """
            Query: "\(query)"
            
            Rate these \(batch.count) videos (0-100):
            \(batchInfo)
            
            Return exactly \(batch.count) comma-separated numbers, one for each video.
            """
            
            do {
                guard let systemMessage = try? ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt),
                      let userMessage = try? ChatQuery.ChatCompletionMessageParam(role: .user, content: userContent) else {
                    logger.error("Failed to create chat messages")
                    throw AISearchError.rankingFailed
                }
                
                let chatQuery = ChatQuery(
                    messages: [systemMessage, userMessage],
                    model: .gpt4_turbo_preview
                )
                
                logger.debug("Sending ranking request to GPT for batch \(batchStart/BATCH_SIZE + 1)")
                let result = try await client.chats(query: chatQuery)
                
                guard case let .string(content) = result.choices.first?.message.content else {
                    logger.error("No content in GPT response")
                    throw AISearchError.rankingFailed
                }
                
                logger.debug("Received GPT response: \(content)")
                
                // Clean and parse the response
                let cleanContent = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                let scoreStrings = cleanContent.split(separator: ",")
                
                logger.debug("Split response into \(scoreStrings.count) parts")
                
                let scores = scoreStrings.compactMap { substring -> Double? in
                    let trimmed = substring.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                    guard let score = Double(trimmed) else {
                        logger.error("Failed to parse score: \(trimmed)")
                        return nil
                    }
                    guard score >= 0 && score <= 100 else {
                        logger.error("Score out of range: \(score)")
                        return nil
                    }
                    return score
                }
                
                logger.debug("Successfully parsed \(scores.count) scores")
                
                // Verify we have the correct number of scores for this batch
                guard scores.count == batch.count else {
                    logger.error("Error: Score count (\(scores.count)) doesn't match batch size (\(batch.count))")
                    throw AISearchError.rankingFailed
                }
                
                // Add batch results to overall results
                let batchResults = Array(zip(batch, scores))
                allRankedVideos.append(contentsOf: batchResults)
                
                logger.debug("Added batch \(batchStart/BATCH_SIZE + 1) results")
                
            } catch {
                logger.error("Error processing batch \(batchStart/BATCH_SIZE + 1): \(error)")
                throw AISearchError.rankingFailed
            }
        }
        
        // Sort all results by score and return videos
        let rankedVideos = allRankedVideos
            .sorted { $0.score > $1.score }
            .map { $0.video }
        
        logger.info("Successfully ranked all \(rankedVideos.count) videos")
        
        // Print final rankings for debugging
        logger.debug("=== FINAL RANKED RESULTS ===")
        for (index, result) in allRankedVideos.sorted(by: { $0.score > $1.score }).enumerated() {
            logger.debug("Rank \(index + 1): \(result.video.title) (Score: \(result.score))")
        }
        logger.debug("=========================")
        
        return rankedVideos
    }
    
    /// Parse scores from GPT response
    private func parseScores(from content: String) -> [Double]? {
        let scores = content.split(separator: ",").compactMap { substring -> Double? in
            let trimmed = substring.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let score = Double(trimmed), score >= 0, score <= 100 else { return nil }
            return score
        }
        return scores.isEmpty ? nil : scores
    }
    
    /// Start a new search task
    func startTask() -> UUID {
        let taskId = UUID()
        activeTasks.insert(taskId)
        return taskId
    }
    
    /// Cancel a specific task
    func cancelTask(_ taskId: UUID) {
        activeTasks.remove(taskId)
    }
    
    /// Nonisolated method to handle task cancellation
    nonisolated func handleTaskCancellation(_ taskId: UUID) {
        Task { await cancelTask(taskId) }
    }
    
    /// Process a natural language query to extract search parameters
    func processNaturalLanguageQuery(_ query: String, taskId: UUID) async throws -> (query: String, filters: [String: String]) {
        guard activeTasks.contains(taskId) else { throw AISearchError.cancelled }
        
        let client = try getClient()
        
        let systemPrompt = """
        You are a video search expert. Convert natural language queries into structured search parameters.
        Return ONLY a JSON object with these fields (no other text):
        {
          "query": "main search terms",
          "year": "time period or null",
          "genre": "video category or null",
          "type": "content type or null",
          "subject": "subject matter or null"
        }

        Examples:
        Input: "funny cat videos from the 90s"
        {
          "query": "cats funny",
          "year": "1990s",
          "genre": "funny",
          "type": "videos",
          "subject": "cats"
        }

        Input: "educational documentaries about space"
        {
          "query": "space education",
          "year": null,
          "genre": "educational",
          "type": "documentaries",
          "subject": "space"
        }

        Input: "funny"
        {
          "query": "funny",
          "year": null,
          "genre": "funny",
          "type": "videos",
          "subject": "comedy"
        }
        """
        
        let userContent = "Process this query: \(query.cleaningHTMLTags())"
        
        // Create chat messages without optionals
        guard let systemMessage = try? ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt),
              let userMessage = try? ChatQuery.ChatCompletionMessageParam(role: .user, content: userContent) else {
            logger.error("Failed to create chat messages")
            throw AISearchError.processingFailed
        }
        
        let chatQuery = ChatQuery(
            messages: [systemMessage, userMessage],
            model: .gpt4_turbo_preview
        )
        
        do {
            let result = try await client.chats(query: chatQuery)
            guard case let .string(content) = result.choices.first?.message.content else {
                logger.error("No content in GPT response")
                throw AISearchError.processingFailed
            }
            
            logger.debug("GPT Response: \(content)")
            
            // Try to extract JSON from the response (in case there's any extra text)
            guard let jsonStart = content.firstIndex(of: "{"),
                  let jsonEnd = content.lastIndex(of: "}") else {
                logger.error("No valid JSON found in response")
                throw AISearchError.processingFailed
            }
            
            let jsonString = String(content[jsonStart...jsonEnd])
            logger.debug("Extracted JSON: \(jsonString)")
            
            // First parse as Any to handle null values
            guard let data = jsonString.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                logger.error("Failed to parse JSON as dictionary")
                throw AISearchError.processingFailed
            }
            
            // Convert the values to strings, replacing null with empty string
            var params: [String: String] = [:]
            for (key, value) in jsonObject {
                if let strValue = value as? String {
                    params[key] = strValue == "null" ? "" : strValue
                } else if value is NSNull {
                    params[key] = ""
                } else {
                    params[key] = "\(value)"
                }
            }
            
            logger.debug("Parsed parameters: \(params)")
            
            // Build the Internet Archive query string
            var queryParts: [String] = []
            
            // Add main search terms
            if let mainQuery = params["query"], !mainQuery.isEmpty {
                // Split query into terms and wrap each in quotes for exact matching
                let terms = mainQuery.split(separator: " ")
                    .map { "\"\($0)\"" }
                    .joined(separator: " OR ")
                queryParts.append("(title:(\(terms)) OR description:(\(terms)))")
            }
            
            // Add year filter
            if let year = params["year"], !year.isEmpty {
                let yearFilter = processYearFilter(year)
                if !yearFilter.isEmpty {
                    queryParts.append(yearFilter)
                }
            }
            
            // Add genre/type/subject filters
            for (key, value) in params where !value.isEmpty {
                if key != "query" && key != "year" {
                    // Use both subject and description for better matches
                    queryParts.append("(subject:\"\(value)\" OR description:\"\(value)\")")
                }
            }
            
            let finalQuery = queryParts.isEmpty ? query : queryParts.joined(separator: " AND ")
            logger.debug("Final query: \(finalQuery)")
            
            return (query: finalQuery, filters: params)
        } catch {
            logger.error("Error processing query: \(error)")
            throw AISearchError.processingFailed
        }
    }
    
    /// Helper function to process year filters
    private func processYearFilter(_ year: String) -> String {
        let year = year.lowercased()
        if year.contains("90s") || year.contains("1990s") {
            return "year:[1990 TO 1999]"
        } else if year.contains("80s") || year.contains("1980s") {
            return "year:[1980 TO 1989]"
        } else if year.contains("2000s") {
            return "year:[2000 TO 2009]"
        } else if year.contains("2010s") {
            return "year:[2010 TO 2019]"
        } else if year.contains("2020s") {
            return "year:[2020 TO 2029]"
        }
        
        // Try to extract specific year range
        let numbers = year.components(separatedBy: CharacterSet.decimalDigits.inverted)
            .compactMap { Int($0) }
            .filter { $0 >= 1900 && $0 <= 2030 }
        
        if numbers.count == 2 {
            return "year:[\(numbers[0]) TO \(numbers[1])]"
        } else if numbers.count == 1 {
            return "year:\(numbers[0])"
        }
        
        return ""
    }
}

// MARK: - Combine Extensions
extension AISearchService {
    func searchAndRankVideosPublisher(videos: [ArchiveVideo], query: String) -> AnyPublisher<[ArchiveVideo], Error> {
        let taskId = startTask()
        return Future { [weak self] promise in
            Task {
                do {
                    let result = try await self?.searchAndRankVideos(videos, query: query, taskId: taskId)
                    promise(.success(result ?? []))
                } catch {
                    promise(.failure(error))
                }
            }
        }
        .handleEvents(receiveCancel: { [weak self] in
            self?.handleTaskCancellation(taskId)
        })
        .eraseToAnyPublisher()
    }
} 