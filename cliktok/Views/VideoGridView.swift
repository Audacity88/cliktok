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
    @State private var showVideoPlayer = false
    @State private var isNavigating = false
    
    private let spacing: CGFloat = 1
    private let columns = [
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1),
        GridItem(.flexible(), spacing: 1)
    ]
    
    init(videos: [Video], showBackButton: Bool = false, clearSearchOnDismiss: Binding<Bool> = .constant(false)) {
        self.videos = videos
        self.showBackButton = showBackButton
        self._clearSearchOnDismiss = clearSearchOnDismiss
    }
    
    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: spacing) {
                ForEach(videos, id: \.stableId) { video in
                    GeometryReader { geometry in
                        let width = geometry.size.width
                        let height = width * (4/3)
                        
                        VideoThumbnailView(video: video)
                            .aspectRatio(9/16, contentMode: .fill)
                            .frame(width: width, height: height)
                            .clipped()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if !isNavigating {
                                    isNavigating = true
                                    selectedVideo = video
                                    showVideoPlayer = true
                                }
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
        .fullScreenCover(isPresented: $showVideoPlayer) {
            isNavigating = false
            selectedVideo = nil
        } content: {
            if let video = selectedVideo {
                UnifiedVideoView(
                    mode: .grid,
                    videos: videos,
                    startingVideo: video,
                    showBackButton: true,
                    clearSearchOnDismiss: $clearSearchOnDismiss,
                    feedViewModel: feedViewModel
                )
                .background(TransparentBackground())
                .edgesIgnoringSafeArea(.all)
                .interactiveDismissDisabled()
            }
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
            
            // Caption overlay at the bottom
            VStack {
                Spacer()
                Text(video.caption.cleaningHTMLTags())
                    .font(.caption)
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.black.opacity(0.5))
            }
        }
    }
}

struct TransparentBackground: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        DispatchQueue.main.async {
            view.superview?.superview?.backgroundColor = .clear
        }
        return view
    }
    
    func updateUIView(_ uiView: UIView, context: Context) {}
}
