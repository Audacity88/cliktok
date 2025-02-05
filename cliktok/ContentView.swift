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
                            Button(action: {
                                showingTestData = true
                            }) {
                                Image(systemName: "plus.circle")
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .sheet(isPresented: $showingTestData) {
                        TestDataView()
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
