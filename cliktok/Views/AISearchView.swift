import SwiftUI

struct AISearchView: View {
    @StateObject private var viewModel = AISearchViewModel()
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var searchMode: SearchMode = .ai
    @FocusState private var isSearchFocused: Bool
    @State private var hashtagSearchText: String = ""
    
    enum SearchMode {
        case ai
        case hashtag
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Search Mode Toggle
                Picker("Search Mode", selection: $searchMode) {
                    Text("AI Search").tag(SearchMode.ai)
                    Text("Hashtag").tag(SearchMode.hashtag)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                
                // Search Header
                if searchMode == .ai {
                    aiSearchHeader
                } else {
                    hashtagSearchHeader
                }
                
                // Results or Loading
                Group {
                    if viewModel.isLoading {
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
                        Task {
                            await viewModel.performSearch()
                        }
                    }
                
                if !viewModel.searchQuery.isEmpty {
                    Button(action: {
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
                        if newValue.isEmpty {
                            feedViewModel.searchResults.removeAll()
                        } else {
                            Task {
                                await feedViewModel.searchVideos(hashtag: newValue)
                            }
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
        ScrollView {
            LazyVStack(spacing: 16) {
                ForEach(viewModel.searchResults, id: \.id) { archiveVideo in
                    let video = Video(
                        id: nil,
                        archiveIdentifier: archiveVideo.id,
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
                    NavigationLink(destination: VideoPlayerView(
                        video: video,
                        showBackButton: true,
                        clearSearchOnDismiss: .constant(false),
                        isVisible: .constant(true),
                        showCreator: true
                    )
                    .environmentObject(feedViewModel)) {
                        VideoResultCard(video: archiveVideo)
                    }
                }
            }
            .padding(.horizontal)
        }
    }
    
    private var hashtagResultsView: some View {
        VideoGridView(videos: feedViewModel.searchResults)
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

struct VideoResultCard: View {
    let video: ArchiveVideo
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(.headline)
                .lineLimit(2)
            
            if let description = video.description {
                Text(description)
                    .font(.subheadline)
                    .foregroundColor(.gray)
                    .lineLimit(3)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(colorScheme == .dark ? Color(.systemGray6) : .white)
                .shadow(radius: 2)
        )
    }
}

#Preview {
    AISearchView()
        .environmentObject(VideoFeedViewModel())
} 