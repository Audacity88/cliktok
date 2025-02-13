import Foundation
import OpenAI
import Combine

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
    
    // Maximum number of search results to process and display
    private let MAX_SEARCH_RESULTS = 5
    
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
        
        print("Starting ranking for \(videos.count) videos with query: \(query)")
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
        
        // Prepare video information with numbering for clearer context
        let videosInfo = videos.prefix(MAX_SEARCH_RESULTS).enumerated().map { index, video in
            """
            [\(index + 1)]
            Title: \(video.title)
            Description: \(video.description?.cleaningHTMLTags() ?? "No description")
            ---
            """
        }.joined(separator: "\n")
        
        let userContent = """
        Query: "\(query)"
        
        Rate these videos (0-100):
        \(videosInfo)
        
        Return only comma-separated numbers.
        """
        
        print("Prepared ranking prompt with \(videos.count) videos")
        
        do {
            // Create chat messages without optionals
            guard let systemMessage = try? ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt),
                  let userMessage = try? ChatQuery.ChatCompletionMessageParam(role: .user, content: userContent) else {
                print("Failed to create chat messages")
                throw AISearchError.rankingFailed
            }
            
            let chatQuery = ChatQuery(
                messages: [systemMessage, userMessage],
                model: .gpt3_5Turbo
            )
            
            print("Sending ranking request to GPT")
            let result = try await client.chats(query: chatQuery)
            
            guard case let .string(content) = result.choices.first?.message.content else {
                print("Error: No content in GPT response")
                throw AISearchError.rankingFailed
            }
            
            print("Received GPT response: \(content)")
            
            // Clean and parse the response
            let cleanContent = content.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
            let scoreStrings = cleanContent.split(separator: ",")
            
            print("Split response into \(scoreStrings.count) parts")
            
            let scores = scoreStrings.compactMap { substring -> Double? in
                let trimmed = substring.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                guard let score = Double(trimmed) else {
                    print("Failed to parse score: \(trimmed)")
                    return nil
                }
                guard score >= 0 && score <= 100 else {
                    print("Score out of range: \(score)")
                    return nil
                }
                return score
            }
            
            print("Successfully parsed \(scores.count) scores")
            
            guard scores.count == videos.prefix(MAX_SEARCH_RESULTS).count else {
                print("Error: Score count (\(scores.count)) doesn't match video count (\(videos.prefix(MAX_SEARCH_RESULTS).count))")
                throw AISearchError.rankingFailed
            }
            
            // Combine videos with scores and sort
            let rankedVideos = Array(zip(videos.prefix(MAX_SEARCH_RESULTS), scores))
                .sorted { $0.1 > $1.1 }
                .map { $0.0 }
            
            print("Successfully ranked \(rankedVideos.count) videos")
            
            // Print rankings for debugging
            for (index, video) in rankedVideos.enumerated() {
                print("Rank \(index + 1): \(video.title) (Score: \(scores[index]))")
            }
            
            return rankedVideos
            
        } catch let error as AISearchError {
            print("AISearchError during ranking: \(error.localizedDescription)")
            throw error
        } catch {
            print("Unexpected error during ranking: \(error.localizedDescription)")
            throw AISearchError.rankingFailed
        }
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
            print("Failed to create chat messages")
            throw AISearchError.processingFailed
        }
        
        let chatQuery = ChatQuery(
            messages: [systemMessage, userMessage],
            model: .gpt3_5Turbo
        )
        
        do {
            let result = try await client.chats(query: chatQuery)
            guard case let .string(content) = result.choices.first?.message.content else {
                print("No content in GPT response")
                throw AISearchError.processingFailed
            }
            
            print("GPT Response: \(content)")
            
            // Try to extract JSON from the response (in case there's any extra text)
            guard let jsonStart = content.firstIndex(of: "{"),
                  let jsonEnd = content.lastIndex(of: "}") else {
                print("No valid JSON found in response")
                throw AISearchError.processingFailed
            }
            
            let jsonString = String(content[jsonStart...jsonEnd])
            print("Extracted JSON: \(jsonString)")
            
            // First parse as Any to handle null values
            guard let data = jsonString.data(using: .utf8),
                  let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                print("Failed to parse JSON as dictionary")
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
            
            print("Parsed parameters: \(params)")
            
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
            print("Final query: \(finalQuery)")
            
            return (query: finalQuery, filters: params)
        } catch {
            print("Error processing query: \(error)")
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