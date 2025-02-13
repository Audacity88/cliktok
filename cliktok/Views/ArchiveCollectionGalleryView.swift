import SwiftUI
import UIKit

struct ArchiveCollectionGalleryView: View {
    @EnvironmentObject var viewModel: ArchiveVideoViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var selectedCollection: ArchiveCollection?
    
    private let columns = [
        GridItem(.flexible()),
        GridItem(.flexible())
    ]
    
    var body: some View {
        NavigationView {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(viewModel.collections) { collection in
                        CollectionCard(collection: collection)
                            .onTapGesture {
                                selectedCollection = collection
                                Task {
                                    await viewModel.loadCollectionVideos(for: collection)
                                }
                                dismiss()
                            }
                    }
                }
                .padding()
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
}

struct CollectionCard: View {
    let collection: ArchiveCollection
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let thumbnailURL = collection.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                CachedAsyncImage(url: url) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(width: UIScreen.main.bounds.width/2 - 20, height: 120)
                        .clipped()
                        .contentShape(Rectangle())
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .frame(height: 120)
                        .overlay(ProgressView())
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.white)
                    )
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(collection.title)
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.green)
                    .lineLimit(1)
                
                Text(collection.description)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.gray)
                    .lineLimit(2)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .background(Color.black)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.green.opacity(0.5), lineWidth: 1)
        )
    }
}
