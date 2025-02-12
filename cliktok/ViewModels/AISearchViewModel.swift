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
            // Build search query based on searchQuery
            let searchTerm = searchQuery.isEmpty ? "random" : searchQuery
            let queryString = """
            (title:"\(searchTerm)" OR description:"\(searchTerm)") AND \
            (mediatype:movies OR mediatype:movingimage) AND \
            -collection:test_videos AND \
            (format:mp4 OR format:h.264 OR format:512kb)
            """
            
            print("Searching with query: \(queryString)")
            
            // Search Internet Archive with multiple results
            let results = try await archiveAPI.fetchCollectionItems(
                query: queryString,
                offset: 0,
                limit: 5  // Fetch 5 results
            )
            
            print("Found \(results.count) initial results")
            
            // Only proceed if we haven't been cancelled
            guard currentTaskId == taskId else {
                print("Search was cancelled, stopping result processing")
                return
            }
            
            // Process all results
            if !results.isEmpty {
                let rankedResults = try await aiService.searchAndRankVideos(results, query: searchQuery, taskId: taskId)
                
                // Check again for cancellation
                guard currentTaskId == taskId else {
                    print("Search was cancelled during ranking")
                    return
                }
                
                // Update searchResults
                await MainActor.run {
                    searchResults = rankedResults
                }
                
                // Notify about each result
                for video in rankedResults {
                    print("Processing video: \(video.identifier)")
                    if let callback = callback {
                        print("Calling onResultFound callback for \(video.identifier)")
                        await MainActor.run {
                            callback(video)
                        }
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