import SwiftUI

struct HashtagSearchView: View {
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var hasSearchResults = false
    @FocusState private var isSearchFocused: Bool
    
    var body: some View {
        NavigationView {
            VStack {
                // Search bar with HashtagTextField
                HStack {
                    HashtagTextField(text: $searchText, placeholder: "Search hashtags...")
                        .focused($isSearchFocused)
                        .onChange(of: searchText) { oldValue, newValue in
                            if newValue.isEmpty {
                                feedViewModel.clearSearch()
                                hasSearchResults = false
                            } else {
                                Task {
                                    await performSearch()
                                }
                            }
                        }
                }
                .padding()
                
                if feedViewModel.isSearching {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = feedViewModel.searchError {
                    Text("Error: \(error.localizedDescription)")
                        .foregroundColor(.red)
                        .padding()
                } else if searchText.isEmpty && !hasSearchResults {
                    // Show trending or suggested hashtags
                    Text("Try searching for #funny, #dance, or #music")
                        .foregroundColor(.gray)
                        .padding()
                } else if feedViewModel.searchResults.isEmpty && !searchText.isEmpty {
                    Text("No videos found")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    // Show search results in a grid
                    VideoGridView(videos: feedViewModel.searchResults, showBackButton: true)
                        .padding(.horizontal, 1)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isSearchFocused || hasSearchResults {
                        Button(action: {
                            if hasSearchResults {
                                searchText = ""
                                feedViewModel.clearSearch()
                                hasSearchResults = false
                            }
                            isSearchFocused = false
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.white)
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Color.black, for: .navigationBar)
        }
    }
    
    private func performSearch() async {
        guard !searchText.isEmpty else {
            feedViewModel.clearSearch()
            hasSearchResults = false
            return
        }
        
        // Get all hashtags from the search text
        let hashtags = searchText.split(separator: " ").map(String.init)
        
        // Search for each hashtag
        for hashtag in hashtags {
            await feedViewModel.searchVideos(hashtag: hashtag)
        }
        
        hasSearchResults = true
    }
} 