import SwiftUI
import UIKit

struct RecommendationsView: View {
    @StateObject private var viewModel = RecommendationsViewModel()
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @Environment(\.colorScheme) private var colorScheme
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if viewModel.isLoading {
                    loadingView
                } else if let error = viewModel.error {
                    errorView(message: error)
                } else {
                    contentView
                }
            }
            .padding()
        }
        .navigationTitle("For You")
        .navigationBarTitleDisplayMode(.large)
        .task {
            await viewModel.loadRecommendations()
        }
        .refreshable {
            await viewModel.loadRecommendations()
        }
    }
    
    private var loadingView: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("Analyzing your preferences...")
                    .foregroundColor(.secondary)
                    .font(.headline)
            }
            .padding(.top, 20)
            
            if !viewModel.tippedVideos.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Based on your tips for:")
                        .foregroundColor(.secondary)
                        .font(.headline)
                    
                    ForEach(viewModel.visibleTippedVideos) { video in
                        HStack(spacing: 12) {
                            AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { image in
                                image
                                    .resizable()
                                    .aspectRatio(contentMode: .fill)
                            } placeholder: {
                                Color.gray.opacity(0.3)
                            }
                            .frame(width: 60, height: 40)
                            .cornerRadius(6)
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text(video.caption)
                                    .foregroundColor(.primary)
                                    .lineLimit(1)
                                    .font(.subheadline)
                                
                                if let description = video.description {
                                    Text(description)
                                        .foregroundColor(.secondary)
                                        .lineLimit(1)
                                        .font(.caption)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                        .transition(.asymmetric(
                            insertion: .opacity.combined(with: .move(edge: .trailing)),
                            removal: .opacity.combined(with: .move(edge: .leading))
                        ))
                    }
                    
                    if viewModel.tippedVideos.count > 8 {
                        // Scroll indicator dots
                        HStack(spacing: 4) {
                            ForEach(0..<min(8, viewModel.tippedVideos.count), id: \.self) { index in
                                Circle()
                                    .fill(index < viewModel.visibleTippedVideos.count ? Color.accentColor : Color.gray.opacity(0.3))
                                    .frame(width: 6, height: 6)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 8)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(UIColor.systemBackground))
                        .shadow(radius: 2)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal)
        .padding(.vertical, 20)
    }
    
    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 50))
                .foregroundColor(.orange)
            
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 50)
    }
    
    private var contentView: some View {
        VStack(spacing: 24) {
            // Interests Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Your Interests")
                
                FlowLayout(spacing: 8) {
                    ForEach(viewModel.interests, id: \.self) { interest in
                        InterestTag(text: interest)
                    }
                }
            }
            
            // Categories Section
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Top Categories")
                
                HStack(spacing: 12) {
                    ForEach(viewModel.topCategories, id: \.self) { category in
                        CategoryCard(category: category)
                    }
                }
            }
            
            // AI Insight
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("AI Insight")
                
                Text(viewModel.explanation)
                    .foregroundColor(.secondary)
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(UIColor.systemBackground))
                            .shadow(radius: 2)
                    )
            }
            
            // Recommended Videos
            VStack(alignment: .leading, spacing: 12) {
                sectionHeader("Recommended Videos")
                
                LazyVStack(spacing: 16) {
                    ForEach(viewModel.recommendedVideos) { video in
                        let destination = VideoPlayerView(video: video, isVisible: .constant(true))
                            .environmentObject(feedViewModel)
                        NavigationLink(destination: destination) {
                            RecommendedVideoRow(video: video)
                        }
                    }
                }
            }
        }
    }
    
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .fontWeight(.bold)
    }
}

struct InterestTag: View {
    let text: String
    
    var body: some View {
        Text(text)
            .font(.subheadline)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.1))
            )
            .foregroundColor(.accentColor)
    }
}

struct CategoryCard: View {
    let category: String
    
    var body: some View {
        VStack {
            Image(systemName: categoryIcon)
                .font(.system(size: 30))
                .foregroundColor(.accentColor)
            
            Text(category)
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(radius: 2)
        )
    }
    
    private var categoryIcon: String {
        switch category.lowercased() {
        case let c where c.contains("music"): return "music.note"
        case let c where c.contains("gaming"): return "gamecontroller"
        case let c where c.contains("education"): return "book"
        case let c where c.contains("sports"): return "sportscourt"
        case let c where c.contains("tech"): return "laptopcomputer"
        case let c where c.contains("food"): return "fork.knife"
        case let c where c.contains("travel"): return "airplane"
        default: return "star"
        }
    }
}

struct RecommendedVideoRow: View {
    let video: Video
    
    var body: some View {
        HStack(spacing: 12) {
            // Thumbnail
            AsyncImage(url: URL(string: video.thumbnailURL ?? "")) { image in
                image
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } placeholder: {
                Color.gray.opacity(0.3)
            }
            .frame(width: 120, height: 80)
            .cornerRadius(8)
            
            // Video Info
            VStack(alignment: .leading, spacing: 4) {
                Text(video.caption)
                    .font(.headline)
                    .lineLimit(2)
                
                if let description = video.description {
                    Text(description)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack {
                    Image(systemName: "eye")
                    Text("\(video.views)")
                    
                    Image(systemName: "heart")
                    Text("\(video.likes)")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(UIColor.systemBackground))
                .shadow(radius: 2)
        )
    }
}

// Helper view for flowing layout of tags
struct FlowLayout: Layout {
    var spacing: CGFloat
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(in: proposal.width ?? 0, subviews: subviews, spacing: spacing)
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(in: bounds.width, subviews: subviews, spacing: spacing)
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: result.positions[index].x + bounds.minX,
                                    y: result.positions[index].y + bounds.minY),
                         proposal: ProposedViewSize(result.sizes[index]))
        }
    }
    
    private struct FlowResult {
        var sizes: [CGSize]
        var positions: [CGPoint]
        var size: CGSize
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            sizes = subviews.map { $0.sizeThatFits(.unspecified) }
            positions = []
            
            var currentX: CGFloat = 0
            var currentY: CGFloat = 0
            var lineHeight: CGFloat = 0
            var maxWidth: CGFloat = 0
            
            for size in sizes {
                if currentX + size.width > maxWidth && currentX > 0 {
                    currentX = 0
                    currentY += lineHeight + spacing
                    lineHeight = 0
                }
                
                positions.append(CGPoint(x: currentX, y: currentY))
                currentX += size.width + spacing
                lineHeight = max(lineHeight, size.height)
                maxWidth = max(maxWidth, currentX)
            }
            
            size = CGSize(width: maxWidth, height: currentY + lineHeight)
        }
    }
} 