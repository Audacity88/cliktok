import SwiftUI

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
            .navigationTitle("Archive Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
            .task {
                // Prefetch all collection thumbnails
                let urls = viewModel.collections.compactMap { collection in
                    collection.thumbnailURL.flatMap { URL(string: $0) }
                }
                ImageCache.shared.prefetchImages(urls)
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
                        .frame(height: 120)
                        .clipped()
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
