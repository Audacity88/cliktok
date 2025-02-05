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
    @Environment(\.modelContext) private var modelContext
    @Query private var items: [Item]

    var body: some View {
        NavigationView {
            if authManager.isAuthenticated {
                List {
                    ForEach(items) { item in
                        NavigationLink(
                            destination: Text("Item at \(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))")
                        ) {
                            Text(item.timestamp, format: Date.FormatStyle(date: .numeric, time: .standard))
                        }
                    }
                    .onDelete(perform: deleteItems)
                }
                .navigationTitle("Items")
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        EditButton()
                    }
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button(action: addItem) {
                            Label("Add Item", systemImage: "plus")
                        }
                    }
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button(action: {
                            try? authManager.signOut()
                        }) {
                            Text("Sign Out")
                        }
                    }
                }
            } else {
                LoginView()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func addItem() {
        withAnimation {
            let newItem = Item(timestamp: Date())
            modelContext.insert(newItem)
        }
    }

    private func deleteItems(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(items[index])
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Item.self, inMemory: true)
}
