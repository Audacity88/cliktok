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
        }
    }
}

struct CollectionCard: View {
    let collection: ArchiveCollection
    
    var body: some View {
        VStack {
            if let thumbnailURL = collection.thumbnailURL {
                AsyncImage(url: URL(string: thumbnailURL)) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } placeholder: {
                    Color.gray
                }
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.gray.opacity(0.3))
                    .frame(height: 120)
                    .overlay(
                        Image(systemName: "film")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    )
            }
            
            Text(collection.title)
                .font(.headline)
                .lineLimit(1)
            
            Text(collection.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(radius: 5)
    }
}
