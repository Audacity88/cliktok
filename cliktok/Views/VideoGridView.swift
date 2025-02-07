import SwiftUI
import FirebaseAuth

struct VideoGridView: View {
    let videos: [Video]
    var showBackButton: Bool = false
    @Binding var clearSearchOnDismiss: Bool
    @Environment(\.dismiss) private var dismiss
    @State private var selectedVideo: Video?
    @State private var showEditSheet = false
    @State private var videoToEdit: Video?
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    
    private let spacing: CGFloat = 1
    private let columns = [
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 1),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 1),
        GridItem(.flexible(minimum: 0, maximum: .infinity), spacing: 1)
    ]
    
    init(videos: [Video], showBackButton: Bool = false, clearSearchOnDismiss: Binding<Bool> = .constant(false)) {
        self.videos = videos
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(videos) { video in
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let height = width * (4/3)
                        
                        VideoThumbnailView(video: video)
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedVideo = video
                            }
                            .contextMenu {
                                if video.userID == Auth.auth().currentUser?.uid {
                                    Button(action: {
                                        videoToEdit = video
                                        showEditSheet = true
                                    }) {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    
                                    Button(role: .destructive, action: {
                                        videoToEdit = video
                                        showEditSheet = true
                                    }) {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                    }
                    .aspectRatio(3/4, contentMode: .fit)
                }
            }
            .padding(.horizontal, spacing)
        }
        .navigationBarBackButtonHidden(showBackButton)
        .toolbar {
            if showBackButton {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: {
                        clearSearchOnDismiss = true
                        dismiss()
                    }) {
                        Image(systemName: "chevron.left")
                            .foregroundColor(.primary)
                    }
                }
            }
        }
        .fullScreenCover(item: $selectedVideo) { video in
            VerticalVideoPlayerView(
                videos: videos,
                startingVideo: video,
                showBackButton: true,
                clearSearchOnDismiss: $clearSearchOnDismiss
            )
            .environmentObject(feedViewModel)
            .edgesIgnoringSafeArea(.all)
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: $showEditSheet) {
            if let video = videoToEdit {
                NavigationView {
                    VideoEditView(video: video, isPresented: $showEditSheet)
                        .environmentObject(feedViewModel)
                }
            }
        }
    }
}

struct VideoThumbnailView: View {
    let video: Video
    
    var body: some View {
        ZStack {
            if let thumbnailURL = video.thumbnailURL,
               let url = URL(string: thumbnailURL) {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    Rectangle()
                        .fill(Color.gray.opacity(0.3))
                        .overlay(ProgressView())
                }
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
                    .overlay(
                        Image(systemName: "play.fill")
                            .foregroundColor(.white)
                            .font(.title)
                    )
            }
            
            // Play icon overlay
            Image(systemName: "play.fill")
                .foregroundColor(.white)
                .font(.title2)
                .shadow(radius: 2)
        }
    }
}
