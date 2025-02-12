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
import os

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
    
    private let logger = Logger(subsystem: "gauntletai.cliktok", category: "ContentView")
    
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
        
        logger.debug("🎨 ContentView initialized with UI appearance configuration")
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
                        // Terminal Tab (Main)
                        NavigationStack {
                            TerminalView()
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "terminal")
                            Text("Terminal")
                        }
                        .tag(0)
                        
                        // Archive Tab
                        NavigationStack {
                            UnifiedVideoView(mode: .archive)
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "tv")
                            Text("Archive")
                        }
                        .tag(1)
                        
                        // Home Tab
                        NavigationStack {
                            UnifiedVideoView(mode: .feed)
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "house.fill")
                            Text("Home")
                        }
                        .tag(2)
                        
                        // Search Tab
                        NavigationStack {
                            AISearchView()
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "magnifyingglass.circle.fill")
                            Text("Search")
                        }
                        .tag(3)
                        
                        // Keep existing Wallet tab
                        NavigationStack {
                            WalletView()
                        }
                        .tabItem {
                            Image(systemName: "dollarsign.circle.fill")
                            Text("Wallet")
                        }
                        .tag(4)
                        
                        // Keep existing Upload tab
                        NavigationStack {
                            VideoUploadView(scrollToTop: $scrollToTop, onDismiss: {
                                switchToTab(0)
                                scrollToTop = true
                            })
                            .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "plus.square.fill")
                            Text("Upload")
                        }
                        .tag(5)
                        
                        // Keep existing Profile tab
                        NavigationStack {
                            ProfileView()
                                .environmentObject(feedViewModel)
                        }
                        .tabItem {
                            Image(systemName: "person.fill")
                            Text("Profile")
                        }
                        .tag(6)
                    }
                    .accentColor(.green)
                }
            } else {
                LoginView()
            }
        }
        .task {
            logger.debug("👀 ContentView appeared, checking initialization state")
            // Give time for Firebase and other services to initialize
            await Task.yield()
            logger.debug("✨ Initialization complete, removing loading screen")
            isLoading = false
        }
        .statusBar(hidden: true)
    }
}

#Preview {
    ContentView()
}
