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
    
    private init() {}
    
    private func getClient() throws -> OpenAI {
        if let client = client {
            return client
        }
        
        guard let apiKey = ProcessInfo.processInfo.environment["OPENAI_API_KEY"], !apiKey.isEmpty else {
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
        
        let client = try getClient()
        
        // Use GPT-3.5 for faster ranking
        let systemPrompt = """
        You are a video search expert. Rate each video's relevance to the query from 0-100.
        Consider relevance to query, video quality, and user engagement potential.
        Return ONLY comma-separated numbers (e.g. "90,45,20"). No other text.
        """
        
        let videosInfo = videos.prefix(20).map { video in
            """
            Title: \(video.title)
            Description: \(video.description)
            ---
            """
        }.joined(separator: "\n")
        
        let userContent = "Query: \(query)\n\nVideos:\n\(videosInfo)"
        guard let systemMessage = try? ChatQuery.ChatCompletionMessageParam(role: .system, content: systemPrompt),
              let userMessage = try? ChatQuery.ChatCompletionMessageParam(role: .user, content: userContent) else {
            throw AISearchError.rankingFailed
        }
        
        let chatQuery = ChatQuery(
            messages: [systemMessage, userMessage],
            model: .gpt3_5Turbo // Use GPT-3.5 for faster responses
        )
        
        do {
            let result = try await client.chats(query: chatQuery)
            if case let .string(content) = result.choices.first?.message.content,
               let scores = parseScores(from: content) {
                // Combine with original videos and sort by score
                let rankedVideos = Array(zip(videos.prefix(20), scores))
                    .sorted { $0.1 > $1.1 }
                    .map { $0.0 }
                
                return rankedVideos
            }
            throw AISearchError.rankingFailed
        } catch {
            throw AISearchError.rankingFailed
        }
    }
    
    /// Parse scores from GPT response
    private func parseScores(from content: String) -> [Double]? {
        let scores = content.split(separator: ",").compactMap { substring -> Double? in
            Double(substring.trimmingCharacters(in: .whitespacesAndNewlines))
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