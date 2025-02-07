//
//  ContentView.swift
//  cliktok
//
//  Created by Daniel Gilles on 2/4/25.
//

import SwiftUI
import SwiftData
import FirebaseAuth

struct ContentView: View {
    @StateObject private var feedViewModel = VideoFeedViewModel()
    @State private var showingVideoUpload = false
    @State private var selectedTab = 0
    @State private var scrollToTop = false
    @State private var isLoading = true
    
    // Use the shared instance as a StateObject to observe changes
    @StateObject private var authManager = AuthenticationManager.shared
    
    init() {
        // Set the unselected color to gray and configure dark appearance
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        
        // Selected state - white
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        // Unselected state - gray
        appearance.stackedLayoutAppearance.normal.iconColor = .gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
        
        // Apply the appearance
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = .gray
    }
    
    func switchToTab(_ tab: Int) {
        selectedTab = tab
    }
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                TabView(selection: $selectedTab) {
                    NavigationStack {
                        VideoFeedView(scrollToTop: $scrollToTop)
                            .environmentObject(feedViewModel)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbarBackground(.visible, for: .navigationBar)
                            .toolbarBackground(Color.black, for: .navigationBar)
                    }
                    .tabItem {
                        Image(systemName: "house.fill")
                        Text("Home")
                    }
                    .tag(0)
                    
                    NavigationStack {
                        HashtagSearchView()
                            .environmentObject(feedViewModel)
                    }
                    .tabItem {
                        Image(systemName: "magnifyingglass")
                        Text("Search")
                    }
                    .tag(1)
                    
                    NavigationStack {
                        WalletView()
                    }
                    .tabItem {
                        Image(systemName: "dollarsign.circle.fill")
                        Text("Wallet")
                    }
                    .tag(2)
                    
                    Button(action: {
                        showingVideoUpload = true
                    }) {
                        Image(systemName: "plus.square.fill")
                            .font(.system(size: 24))
                    }
                    .tabItem {
                        Image(systemName: "plus.square.fill")
                        Text("Upload")
                    }
                    .tag(3)
                    
                    NavigationStack {
                        ProfileView()
                            .environmentObject(feedViewModel)
                    }
                    .tabItem {
                        Image(systemName: "person.fill")
                        Text("Profile")
                    }
                    .tag(4)
                }
                .sheet(isPresented: $showingVideoUpload) {
                    VideoUploadView(scrollToTop: $scrollToTop, onDismiss: {
                        switchToTab(0)  // Switch to home tab
                        scrollToTop = true  // Trigger scroll to top
                    })
                    .environmentObject(feedViewModel)
                }
            } else {
                LoginView()
            }
        }
        .task {
            // Add a small delay to prevent flash of login screen
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
            isLoading = false
        }
    }
}

#Preview {
    ContentView()
}
