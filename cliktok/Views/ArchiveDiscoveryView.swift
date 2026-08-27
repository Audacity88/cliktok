import AVKit
import SwiftUI

struct ArchiveDiscoveryView: View {
    @StateObject private var viewModel = ArchiveDiscoveryViewModel()

    var body: some View {
        Group {
            switch viewModel.state {
            case .idle, .loading:
                ProgressView("Loading Internet Archive…")
            case .empty:
                ContentUnavailableView("No videos available", systemImage: "film")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Archive unavailable", systemImage: "wifi.exclamationmark")
                } description: { Text(message) } actions: {
                    Button("Try Again") { Task { await viewModel.load() } }
                }
            case .loaded(let items):
                List(items) { item in
                    NavigationLink(value: item) {
                        HStack(spacing: 12) {
                            AsyncImage(url: item.thumbnailURL) { image in image.resizable().scaledToFill() }
                                placeholder: { Color.gray.opacity(0.2).overlay { ProgressView() } }
                                .frame(width: 120, height: 76).clipped().cornerRadius(8)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(item.title).font(.headline).lineLimit(2)
                                Text(item.creator ?? "Creator not listed").font(.caption).foregroundStyle(.secondary)
                                if let date = item.date { Text(date).font(.caption2).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                .navigationDestination(for: ArchiveDiscoveryItem.self) { ArchiveDiscoveryDetailView(item: $0) }
            }
        }
        .navigationTitle("Internet Archive")
        .task { if case .idle = viewModel.state { await viewModel.load() } }
    }
}

private struct ArchiveDiscoveryDetailView: View {
    let item: ArchiveDiscoveryItem
    @State private var player: AVPlayer

    init(item: ArchiveDiscoveryItem) {
        self.item = item
        _player = State(initialValue: AVPlayer(url: item.mediaURL))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VideoPlayer(player: player).aspectRatio(16 / 9, contentMode: .fit).background(.black)
                Text(item.title).font(.title2.bold())
                if let creator = item.creator { LabeledContent("Creator", value: creator) }
                if let date = item.date { LabeledContent("Date", value: date) }
                LabeledContent("Identifier", value: item.identifier)
                LabeledContent("License", value: item.license).font(.caption)
                if let description = item.itemDescription { Text(description).font(.body) }
                Link("View on Internet Archive", destination: item.archiveURL)
                    .font(.headline).padding(.vertical, 8)
            }
            .padding()
        }
        .navigationTitle("Archive video")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.pause() }
    }
}
