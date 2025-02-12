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
        
        guard !searchQuery.isEmpty else {
            await clearSearch()
            return
        }
        
        isLoading = true
        errorMessage = nil
        currentTaskId = await aiService.startTask()
        
        guard let taskId = currentTaskId else { return }
        
        do {
            // Search Internet Archive directly with the query
            let results = try await archiveAPI.fetchCollectionItems(
                identifier: "artsandmusicvideos",
                offset: 0,
                limit: 20 // Reduced limit since we only rank 20 anyway
            )
            
            // Rank results using GPT
            let rankedResults = try await aiService.searchAndRankVideos(results, query: searchQuery, taskId: taskId)
            
            // Update UI if this is still the current task
            if currentTaskId == taskId {
                searchResults = rankedResults
                errorMessage = nil
            }
        } catch AISearchError.cancelled {
            // Ignore cancellation errors
        } catch AISearchError.invalidAPIKey {
            errorMessage = "OpenAI API key not configured. Please check your environment variables."
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
        } catch let error as AISearchError {
            errorMessage = error.localizedDescription
        } catch {
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
        
        // Update loading state if this is still the current task
        if currentTaskId == taskId {
            isLoading = false
        }
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