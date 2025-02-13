import Foundation
import SwiftUI
import Combine

@MainActor
class AISearchViewModel: ObservableObject {
    @Published var searchQuery = ""
    @Published var searchResults: [ArchiveVideo] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    
    private let aiService = AISearchService.shared
    private let archiveAPI = InternetArchiveAPI.shared
    private var cancellables = Set<AnyCancellable>()
    private var currentTaskId: UUID?
    
    var onResultFound: ((ArchiveVideo) -> Void)?
    
    init() {
        // Set up search query debouncing
        $searchQuery
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .removeDuplicates()
            .filter { !$0.isEmpty }
            .sink { [weak self] _ in
                Task {
                    await self?.performSearch()
                }
            }
            .store(in: &cancellables)
    }
    
    func performSearch() async {
        // Cancel previous task if any
        if let taskId = currentTaskId {
            await aiService.handleTaskCancellation(taskId)
        }
        
        isLoading = true
        errorMessage = nil
        searchResults.removeAll()
        currentTaskId = await aiService.startTask()
        
        guard let taskId = currentTaskId else { return }
        
        // Store callback locally to ensure it's not cleared during search
        let callback = onResultFound
        
        do {
            // Process natural language query first
            let searchTerm = searchQuery.isEmpty ? "random" : searchQuery
            let (processedQuery, filters) = try await aiService.processNaturalLanguageQuery(searchTerm, taskId: taskId)
            
            print("Original query: \(searchTerm)")
            print("Processed query: \(processedQuery)")
            print("Filters: \(filters)")
            
            // Build the final query string with media type restrictions
            let queryString = """
            (\(processedQuery)) AND \
            (mediatype:movies OR mediatype:movingimage) AND \
            -collection:test_videos AND \
            (format:mp4 OR format:h.264 OR format:512kb)
            """
            
            print("Final search query: \(queryString)")
            
            // Search Internet Archive with multiple results
            let results = try await archiveAPI.fetchCollectionItems(
                query: queryString,
                offset: 0,
                limit: 10 // Match AISearchService.MAX_SEARCH_RESULTS
            )
            
            // Remove duplicates by identifier
            let uniqueResults = Array(Dictionary(grouping: results, by: { $0.identifier }).values.map { $0[0] }.prefix(10))
            
            print("Found \(uniqueResults.count) unique initial results")
            
            // Only proceed if we haven't been cancelled
            guard currentTaskId == taskId else {
                print("Search was cancelled, stopping result processing")
                return
            }
            
            // Show initial results one by one through callback with delay
            for (index, video) in uniqueResults.enumerated() {
                print("Showing initial result [\(index + 1)/\(uniqueResults.count)]: \(video.identifier)")
                
                // Add a small delay between showing each result (200ms)
                if index > 0 {
                    try await Task.sleep(nanoseconds: 200_000_000)
                }
                
                // Show the result on the main actor
                await MainActor.run {
                    callback?(video)
                }
            }
            
            // Process results with AI if we have any
            if !uniqueResults.isEmpty {
                // Add a delay to ensure initial results are displayed
                try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second delay
                
                let rankedResults = try await aiService.searchAndRankVideos(uniqueResults, query: searchQuery, taskId: taskId)
                
                // Check again for cancellation
                guard currentTaskId == taskId else {
                    print("Search was cancelled during ranking")
                    return
                }
                
                // Store ranked results and show them
                await MainActor.run {
                    searchResults = rankedResults
                    
                    // Print debug info about ranked results
                    print("\n=== FINAL RANKED RESULTS ===")
                    for (index, video) in rankedResults.enumerated() {
                        print("[\(index + 1)] \(video.identifier)")
                    }
                    print("=========================\n")
                    
                    // Clear previous results by sending a special signal
                    callback?(ArchiveVideo(identifier: "CLEAR_RESULTS", title: "", videoURL: "", thumbnailURL: "", description: ""))
                    
                    // Show ranked results with delay
                    Task {
                        print("\nDisplaying ranked results:")
                        for (index, video) in rankedResults.enumerated() {
                            if index > 0 {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                            }
                            print("Showing ranked result [\(index + 1)/\(rankedResults.count)]: \(video.identifier)")
                            callback?(video)
                        }
                        
                        // Send end signal after all ranked results are shown
                        try? await Task.sleep(nanoseconds: 200_000_000)
                        callback?(ArchiveVideo(identifier: "END_RANKED_RESULTS", title: "", videoURL: "", thumbnailURL: "", description: ""))
                    }
                }
            } else {
                print("Warning: No initial results found")
                errorMessage = "No results found for: \(searchQuery)"
            }
            
            print("Search complete")
            
        } catch AISearchError.cancelled {
            print("Search cancelled - not treating as an error")
            // Don't set error message for cancellation
        } catch AISearchError.invalidAPIKey {
            errorMessage = "OpenAI API key not configured. Please check your environment variables."
            print("Invalid API key error")
        } catch AISearchError.processingFailed {
            errorMessage = "Failed to process your search query. Please try a different wording."
            print("Query processing failed")
        } catch let error as AISearchError {
            errorMessage = error.localizedDescription
            print("AISearchError: \(error.localizedDescription)")
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
            print("Unexpected error: \(error)")
        }
        
        isLoading = false
    }
    
    func clearSearch() async {
        // Cancel current task if any
        if let taskId = currentTaskId {
            await aiService.handleTaskCancellation(taskId)
            currentTaskId = nil
        }
        
        searchQuery = ""
        searchResults = []
        errorMessage = nil
    }
    
    deinit {
        // Cancel any ongoing task
        if let taskId = currentTaskId {
            Task {
                await aiService.handleTaskCancellation(taskId)
            }
        }
        // Clear Combine subscriptions
        cancellables.removeAll()
    }
} 