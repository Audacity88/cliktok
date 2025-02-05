import SwiftUI
import PhotosUI
import AVKit

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var caption = ""
    @State private var hashtags = ""
    @State private var showingPreview = false
    @State private var videoURL: URL?
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        NavigationView {
            Form {
                Section {
                    PhotosPicker(selection: $selectedItem,
                               matching: .videos,
                               photoLibrary: .shared()) {
                        Label(selectedItem == nil ? "Select Video" : "Change Video",
                              systemImage: "video.badge.plus")
                    }
                    
                    if viewModel.isUploading {
                        ProgressView("Uploading...", value: viewModel.progress, total: 1.0)
                    }
                    
                    if let videoURL = videoURL {
                        Button("Preview Video") {
                            showingPreview = true
                        }
                    }
                }
                
                Section(header: Text("Details")) {
                    TextField("Caption", text: $caption)
                    TextField("Hashtags (comma separated)", text: $hashtags)
                }
                
                Section {
                    Button(action: uploadVideo) {
                        if viewModel.isUploading {
                            ProgressView()
                        } else {
                            Text("Upload Video")
                        }
                    }
                    .disabled(videoURL == nil || caption.isEmpty || viewModel.isUploading)
                }
            }
            .navigationTitle("Upload Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .onChange(of: selectedItem) { newValue in
                if let newValue {
                    handleSelection(newValue)
                }
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(isPresented: $showingPreview) {
                if let videoURL = videoURL {
                    VideoPreviewView(videoURL: videoURL)
                }
            }
            .onAppear {
                viewModel.onUploadComplete = {
                    Task {
                        await feedViewModel.loadInitialVideos()
                        dismiss()
                    }
                }
            }
        }
    }
    
    private func handleSelection(_ item: PhotosPickerItem) {
        Task {
            do {
                guard let videoData = try await item.loadTransferable(type: Data.self) else {
                    throw NSError(domain: "VideoUpload", code: 500, userInfo: [NSLocalizedDescriptionKey: "Failed to load video data"])
                }
                
                // Save to temporary file
                let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
                try videoData.write(to: tempURL)
                
                // Update UI on main thread
                await MainActor.run {
                    self.videoURL = tempURL
                }
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
    
    private func uploadVideo() {
        guard let videoURL = videoURL else { return }
        
        let hashtagArray = hashtags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        Task {
            do {
                try await viewModel.uploadVideo(
                    videoURL: videoURL,
                    caption: caption,
                    hashtags: hashtagArray
                )
            } catch {
                await MainActor.run {
                    alertMessage = error.localizedDescription
                    showAlert = true
                }
            }
        }
    }
}

struct VideoPreviewView: View {
    let videoURL: URL
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationView {
            VideoPlayer(player: AVPlayer(url: videoURL))
                .navigationTitle("Preview")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }
} 