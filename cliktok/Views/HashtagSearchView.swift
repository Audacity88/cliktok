import SwiftUI

struct HashtagSearchView: View {
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var hasSearchResults = false
    @FocusState private var isSearchFocused: Bool
    @State private var keepKeyboardUp = true
    @Environment(\.dismiss) private var dismiss
    @Binding var clearSearchOnDismiss: Bool
    
    init(clearSearchOnDismiss: Binding<Bool> = .constant(false)) {
        self._clearSearchOnDismiss = clearSearchOnDismiss
    }
    
    var body: some View {
        NavigationView {
            ZStack(alignment: .top) {
                Color(uiColor: .systemBackground)
                    .edgesIgnoringSafeArea(.all)
                
                VStack(spacing: 0) {
                    // Search bar with HashtagTextField
                    HStack {
                        HashtagTextField(text: $searchText, placeholder: "Search hashtags...", singleTagMode: true, onTagsChanged: { tags in
                            Task {
                                if tags.isEmpty {
                                    feedViewModel.clearSearch()
                                    hasSearchResults = false
                                } else {
                                    isSearching = true
                                    await performSearch(tags: tags)
                                    isSearching = false
                                }
                            }
                        })
                        .focused($isSearchFocused)
                    }
                    .padding()
                    
                    // Content area
                    ZStack {
                        if isSearching {
                            ProgressView()
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        } else if let error = feedViewModel.searchError {
                            Text("Error: \(error.localizedDescription)")
                                .foregroundColor(.red)
                                .padding()
                        } else if searchText.isEmpty && !hasSearchResults {
                            VStack {
                                Spacer()
                                Text("Try searching for #funny, #dance, or #music")
                                    .foregroundColor(.secondary)
                                    .padding()
                                Spacer()
                            }
                        } else if feedViewModel.searchResults.isEmpty && !searchText.isEmpty {
                            VStack {
                                Spacer()
                                Text("No videos found")
                                    .foregroundColor(.secondary)
                                    .padding()
                                Spacer()
                            }
                        } else {
                            VideoGridView(videos: feedViewModel.searchResults)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(isSearchFocused || hasSearchResults)
            .toolbar {
                if isSearchFocused || hasSearchResults {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            searchText = ""
                            feedViewModel.clearSearch()
                            hasSearchResults = false
                            keepKeyboardUp = false
                            isSearchFocused = false
                            dismiss()
                        }) {
                            Image(systemName: "chevron.left")
                                .foregroundColor(.primary)
                        }
                    }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
            .onAppear {
                keepKeyboardUp = true
                isSearchFocused = true
            }
            .onChange(of: keepKeyboardUp) { oldValue, newValue in
                if newValue {
                    isSearchFocused = true
                }
            }
            .onChange(of: clearSearchOnDismiss) { oldValue, newValue in
                if newValue {
                    searchText = ""
                    feedViewModel.clearSearch()
                    hasSearchResults = false
                    clearSearchOnDismiss = false
                    keepKeyboardUp = true
                    isSearchFocused = true
                }
            }
        }
        .onReceive(Timer.publish(every: 0.1, on: .main, in: .common).autoconnect()) { _ in
            if keepKeyboardUp {
                isSearchFocused = true
            }
        }
    }
    
    private func performSearch(tags: [String]) async {
        guard !tags.isEmpty else {
            feedViewModel.clearSearch()
            hasSearchResults = false
            return
        }
        
        hasSearchResults = true
        
        // Search for each hashtag
        for hashtag in tags {
            await feedViewModel.searchVideos(hashtag: hashtag)
        }
    }
}