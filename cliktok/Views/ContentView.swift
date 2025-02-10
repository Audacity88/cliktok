//
//  ContentView.swift
//  cliktok
//
//  Created by Daniel Gilles on 2/4/25.
//

import SwiftUI
import SwiftData
import FirebaseAuth
import UIKit

struct RetroStatusBar: View {
    @State private var currentTime = Date()
    @State private var batteryLevel: Float = 0.0
    
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    
    var body: some View {
        HStack {
            Text(currentTime, format: .dateTime.hour().minute())
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
            
            Spacer()
            
            Text("\(max(0, Int(batteryLevel * 100)))%")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.green)
        }
        .padding()
        .background(Color.black)
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            batteryLevel = UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : 1.0
        }
        .onDisappear {
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
        .onReceive(timer) { input in
            currentTime = input
            batteryLevel = UIDevice.current.batteryLevel >= 0 ? UIDevice.current.batteryLevel : batteryLevel
        }
    }
}

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
        
        // Selected state - green
        appearance.stackedLayoutAppearance.selected.iconColor = UIColor.systemGreen
        appearance.stackedLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemGreen, .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        appearance.inlineLayoutAppearance.selected.iconColor = UIColor.systemGreen
        appearance.inlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemGreen, .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        appearance.compactInlineLayoutAppearance.selected.iconColor = UIColor.systemGreen
        appearance.compactInlineLayoutAppearance.selected.titleTextAttributes = [.foregroundColor: UIColor.systemGreen, .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        
        // Unselected state - gray
        appearance.stackedLayoutAppearance.normal.iconColor = .gray
        appearance.stackedLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray, .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        appearance.inlineLayoutAppearance.normal.iconColor = .gray
        appearance.inlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray, .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        appearance.compactInlineLayoutAppearance.normal.iconColor = .gray
        appearance.compactInlineLayoutAppearance.normal.titleTextAttributes = [.foregroundColor: UIColor.gray, .font: UIFont.monospacedSystemFont(ofSize: 10, weight: .regular)]
        
        // Apply the appearance
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().unselectedItemTintColor = .gray
        
        // Enable more items
        UITabBar.appearance().itemPositioning = .centered
        UITabBar.appearance().itemSpacing = 32
    }
    
    func switchToTab(_ tab: Int) {
        selectedTab = tab
    }
    
    var body: some View {
        Group {
            if isLoading {
                LoadingView()
            } else if authManager.isAuthenticated {
                ZStack(alignment: .top) {
                    TabView(selection: $selectedTab) {
                        NavigationStack {
                            ArchiveTabView()
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "tv")
                            Text("Archive")
                        }
                        .tag(0)
                        
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
                        .tag(1)
                        
                        NavigationStack {
                            HashtagSearchView()
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "magnifyingglass")
                            Text("Search")
                        }
                        .tag(2)
                        
                        NavigationStack {
                            WalletView()
                        }
                        .tabItem {
                            Image(systemName: "dollarsign.circle.fill")
                            Text("Wallet")
                        }
                        .tag(3)
                        
                        NavigationStack {
                            VideoUploadView(scrollToTop: $scrollToTop, onDismiss: {
                                switchToTab(0)  // Switch to home tab
                                scrollToTop = true  // Trigger scroll to top
                            })
                            .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "plus.square.fill")
                            Text("Upload")
                        }
                        .tag(4)
                        
                        NavigationStack {
                            ProfileView()
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "person.fill")
                            Text("Profile")
                        }
                        .tag(5)
                    }
                    .accentColor(.green)
                    
                    // Remove RetroStatusBar from here since it's now in VideoPlayerView
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
        .statusBar(hidden: true) // Hide system status bar
    }
}

#Preview {
    ContentView()
}
