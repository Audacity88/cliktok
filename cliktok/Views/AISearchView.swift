import SwiftUI
import os

// Add logger instance
private let logger = Logger(component: "AISearchView")

struct AISearchView: View {
    @StateObject private var viewModel = AISearchViewModel()
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchMode: SearchMode = .ai
    @FocusState private var isSearchFocused: Bool
    @State private var hashtagSearchText: String = ""
    @State private var isSearching = false
    
    enum SearchMode {
        case ai
        case hashtag
    }
    
    var body: some View {
        VStack(spacing: 20) {
            // Search Mode Toggle
            Picker("Search Mode", selection: $searchMode) {
                Text("AI Search").tag(SearchMode.ai)
                Text("Hashtag").tag(SearchMode.hashtag)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .onChange(of: searchMode) { newMode in
                logger.debug("Search mode changed to: \(newMode == .ai ? "AI" : "Hashtag")")
                // Clear search results when switching modes
                if newMode == .ai {
                    feedViewModel.clearSearch()
                    hashtagSearchText = ""
                    Task {
                        await viewModel.clearSearch()
                    }
                } else {
                    viewModel.searchResults.removeAll()
                    Task {
                        await viewModel.clearSearch()
                    }
                }
            }
            
            // Search Header
            if searchMode == .ai {
                aiSearchHeader
            } else {
                hashtagSearchHeader
            }
            
            // Results or Loading
            Group {
                if isSearching || viewModel.isLoading {
                    loadingView
                } else if searchMode == .ai && !viewModel.searchResults.isEmpty {
                    aiResultsView
                } else if searchMode == .hashtag && !feedViewModel.searchResults.isEmpty {
                    hashtagResultsView
                } else if let error = viewModel.errorMessage {
                    errorView(message: error)
                } else if let error = feedViewModel.searchError?.localizedDescription {
                    errorView(message: error)
                } else {
                    placeholderView
                }
            }
        }
        .padding(.top)
        .navigationTitle("Search")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var aiSearchHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "magnifyingglass.circle.fill")
                    .foregroundColor(.gray)
                
                TextField("Ask me to find videos...", text: $viewModel.searchQuery)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.search)
                    .onSubmit {
                        logger.debug("Starting AI search for: \(viewModel.searchQuery)")
                        isSearching = true
                        Task {
                            await viewModel.performSearch()
                            isSearching = false
                        }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
                        viewModel.searchQuery = ""
                        viewModel.searchResults.removeAll()
                        Task {
                            await viewModel.clearSearch()
                        }
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal)
            
            Text("Try: \"funny cat videos from the 90s\" or \"educational science documentaries about space\"")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private var hashtagSearchHeader: some View {
        VStack(spacing: 12) {
            HStack {
                Image(systemName: "number.magnifyingglass")
                    .foregroundColor(.gray)
                
                TextField("Search hashtags...", text: $hashtagSearchText)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .submitLabel(.search)
                    .focused($isSearchFocused)
                    .onChange(of: hashtagSearchText) { newValue in
                        logger.debug("Hashtag search text changed to: \(newValue)")
                        if newValue.isEmpty {
                            logger.debug("Clearing search results due to empty search")
                            feedViewModel.clearSearch()
                            isSearching = false
                        } else {
                            logger.debug("Initiating hashtag search for: \(newValue)")
                            isSearching = true
                            Task {
                                await performHashtagSearch(newValue)
                            }
                        }
                    }
                
                if !hashtagSearchText.isEmpty {
                    Button(action: {
                        hashtagSearchText = ""
                        feedViewModel.clearSearch()
                        isSearching = false
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.gray)
                    }
                }
            }
            .padding(.horizontal)
            
            Text("Try: #funny, #dance, or #music")
                .font(.caption)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
    }
    
    private func performHashtagSearch(_ query: String) async {
        logger.debug("Starting search task for hashtag: \(query)")
        await feedViewModel.searchVideos(hashtag: query)
        isSearching = false
        logger.debug("Search task completed. Results count: \(feedViewModel.searchResults.count)")
    }
    
    private var loadingView: some View {
        VStack {
            ProgressView()
                .scaleEffect(1.5)
            Text("Searching videos...")
                .foregroundColor(.gray)
                .padding(.top)
        }
    }
    
    private var aiResultsView: some View {
        let videos = viewModel.searchResults.map { archiveVideo in
            Video(
                id: "ai_\(archiveVideo.identifier)",
                archiveIdentifier: archiveVideo.identifier,
                userID: "archive_user",
                videoURL: archiveVideo.videoURL,
                thumbnailURL: archiveVideo.thumbnailURL,
                caption: archiveVideo.title,
                description: archiveVideo.description,
                hashtags: ["archive"],
                createdAt: Date(),
                likes: 0,
                views: 0
            )
        }
        
        return VideoGridView(
            videos: videos,
            showBackButton: true,
            clearSearchOnDismiss: .constant(false)
        )
        .id(videos.count) // Force view refresh when results change
        .environmentObject(feedViewModel)
    }
    
    private var hashtagResultsView: some View {
        VideoGridView(
            videos: feedViewModel.searchResults,
            showBackButton: true,
            clearSearchOnDismiss: .constant(false)
        )
        .id(feedViewModel.searchResults.count) // Force view refresh when results change
        .environmentObject(feedViewModel)
        .onAppear {
            logger.debug("Hashtag results view appeared with \(feedViewModel.searchResults.count) videos")
        }
    }
    
    private func errorView(message: String) -> some View {
        VStack {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundColor(.red)
            Text(message)
                .foregroundColor(.red)
                .multilineTextAlignment(.center)
                .padding()
        }
    }
    
    private var placeholderView: some View {
        VStack(spacing: 20) {
            Image(systemName: searchMode == .ai ? "magnifyingglass.circle.fill" : "number.magnifyingglass")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            Text(searchMode == .ai ? 
                "Enter a natural language query to search for videos" :
                "Enter a hashtag to search for videos")
                .multilineTextAlignment(.center)
                .foregroundColor(.gray)
        }
    }
}

#Preview {
    AISearchView()
        .environmentObject(VideoFeedViewModel())
} 