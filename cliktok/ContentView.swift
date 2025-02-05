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
    @State private var showingTestData = false
    @State private var showingVideoUpload = false
    
    var body: some View {
        NavigationView {
            if authManager.isAuthenticated {
                VideoFeedView()
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button(action: {
                                try? authManager.signOut()
                            }) {
                                Text("Sign Out")
                                    .foregroundColor(.white)
                            }
                        }
                        
                        ToolbarItem(placement: .navigationBarTrailing) {
                            HStack {
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
                        }
                    }
                    .sheet(isPresented: $showingTestData) {
                        TestDataView()
                    }
                    .sheet(isPresented: $showingVideoUpload) {
                        VideoUploadView()
                    }
            } else {
                LoginView()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }
}

#Preview {
    ContentView()
}
