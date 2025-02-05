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
    @StateObject private var authManager = AuthenticationManager()
    @StateObject private var feedViewModel = VideoFeedViewModel()
    @State private var showingTestData = false
    @State private var showingVideoUpload = false
    @State private var selectedTab = 0
    
    init() {
        // Set the unselected color to gray
        UITabBar.appearance().unselectedItemTintColor = .gray
    }
    
    var body: some View {
        if authManager.isAuthenticated {
            TabView(selection: $selectedTab) {
                NavigationStack {
                    VideoFeedView()
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbarBackground(.visible, for: .navigationBar)
                        .toolbarBackground(Color.black, for: .navigationBar)
                        .navigationBarItems(
                            leading: Button(action: {
                                try? authManager.signOut()
                            }) {
                                Text("Sign Out")
                                    .foregroundColor(.white)
                            },
                            trailing: HStack {
                                Button(action: {
                                    showingVideoUpload = true
                                }) {
                                    Image(systemName: "square.and.arrow.up")
                                        .foregroundColor(.white)
                                }
                                
                                Button(action: {
                                    showingTestData = true
                                }) {
                                    Image(systemName: "plus.circle")
                                        .foregroundColor(.white)
                                }
                            }
                        )
                }
                .tabItem {
                    Image(systemName: "play.circle.fill")
                    Text("Feed")
                }
                .tag(0)
                
                NavigationStack {
                    WalletView()
                }
                .tabItem {
                    Image(systemName: "creditcard.fill")
                    Text("Wallet")
                }
                .tag(1)
            }
            .onChange(of: selectedTab) { oldValue, newValue in
                // Update tab bar appearance based on selected tab
                let tabBarAppearance = newValue == 1 ? lightAppearance : darkAppearance
                UITabBar.appearance().scrollEdgeAppearance = tabBarAppearance
                UITabBar.appearance().standardAppearance = tabBarAppearance
            }
            .sheet(isPresented: $showingTestData) {
                TestDataView()
            }
            .sheet(isPresented: $showingVideoUpload) {
                VideoUploadView()
                    .environmentObject(feedViewModel)
            }
        } else {
            LoginView()
        }
    }
    
    // Store appearances as properties to avoid recreation
    private let lightAppearance: UITabBarAppearance = {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .white
        
        // Selected state - black
        appearance.stackedLayoutAppearance.selected.iconColor = .black
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.black]
        
        // Unselected state - gray
        appearance.stackedLayoutAppearance.normal.iconColor = .gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
        
        return appearance
    }()
    
    private let darkAppearance: UITabBarAppearance = {
        let appearance = UITabBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        
        // Selected state - white
        appearance.stackedLayoutAppearance.selected.iconColor = .white
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.white]
        
        // Unselected state - gray
        appearance.stackedLayoutAppearance.normal.iconColor = .gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray]
        
        return appearance
    }()
}

#Preview {
    ContentView()
}
