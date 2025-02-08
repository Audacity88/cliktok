import SwiftUI
import PhotosUI
import AVKit
import FirebaseAuth

struct VideoUploadView: View {
    @StateObject private var viewModel = VideoUploadViewModel()
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @Binding var scrollToTop: Bool
    let onDismiss: () -> Void
    
    @State private var selectedItem: PhotosPickerItem?
    @State private var caption = ""
    @State private var hashtags = ""
    @State private var showingPreview = false
    @State private var videoURL: URL?
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showingCamera = false
    @State private var showSuccessMessage = false
    @FocusState private var isInputActive: Bool
    
    private func resetUploadForm() {
        videoURL = nil
        caption = ""
        hashtags = ""
        selectedItem = nil
        showSuccessMessage = false
        viewModel.isAdvertisement = false
    }
    
    var body: some View {
        if Auth.auth().currentUser?.isAnonymous == true {
            GuestRestrictedView()
        } else {
            Form {
                if showSuccessMessage {
                    Section {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("Video recorded successfully!")
                                .foregroundColor(.green)
                        }
                        .listRowBackground(Color.green.opacity(0.1))
                    }
                }
                
                if viewModel.isUserMarketer {
                    Section(header: Text("Marketing Options").foregroundColor(.blue)) {
                        Toggle(isOn: $viewModel.isAdvertisement) {
                            Label {
                                Text("Mark as Advertisement")
                            } icon: {
                                Image(systemName: "megaphone.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .tint(.blue)
                    }
                }
                
                Section {
                    // Record new video button
                    Button(action: {
                        showingCamera = true
                    }) {
                        HStack {
                            Image(systemName: "camera.fill")
                                .font(.title2)
                                .foregroundColor(.blue)
                            Text("Record New Video")
                                .foregroundColor(.blue)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }
                    
                    // Choose existing video button
                    PhotosPicker(selection: $selectedItem,
                               matching: .videos,
                               photoLibrary: .shared()) {
                        if selectedItem == nil {
                            HStack {
                                Image(systemName: "photo.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                                Text("Choose from Library")
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        } else {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Change Video")
                                    .foregroundColor(.blue)
                            }
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(8)
                        }
                    }
                    
                    if viewModel.isUploading {
                        ProgressView("Uploading...", value: viewModel.progress, total: 1.0)
                    }
                    
                    if videoURL != nil {
                        Button("Preview Video") {
                            showingPreview = true
                        }
                    }
                }
                
                Section(header: Text("Details")) {
                    TextField("Caption", text: $caption)
                        .textInputAutocapitalization(.sentences)
                        .focused($isInputActive)
                    HashtagTextField(text: $hashtags, placeholder: "Enter hashtags")
                        .focused($isInputActive)
                }
                
                Section {
                    Button(action: uploadVideo) {
                        if viewModel.isUploading {
                            ProgressView()
                        } else {
                            Text("Upload Video")
                                .frame(maxWidth: .infinity)
                                .foregroundColor(.white)
                        }
                    }
                    .disabled(videoURL == nil || caption.isEmpty || viewModel.isUploading)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(videoURL == nil || caption.isEmpty || viewModel.isUploading ? Color.gray : Color.blue)
                            .padding(.vertical, 4)
                    )
                }
            }
            .navigationTitle(viewModel.isUserMarketer ? "Upload Marketing Video" : "Upload Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isInputActive {
                        Button("Done") {
                            isInputActive = false
                        }
                    }
                }
            }
            .onChange(of: selectedItem) { oldValue, newValue in
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
                if let previewURL = videoURL {
                    VideoPreviewView(videoURL: previewURL)
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraView { url in
                    self.videoURL = url
                    self.showSuccessMessage = true
                    
                    // Hide success message after a delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        withAnimation {
                            self.showSuccessMessage = false
                        }
                    }
                }
            }
            .onAppear {
                // Check marketer status immediately when view appears
                viewModel.checkMarketerStatus()
                
                viewModel.onUploadComplete = {
                    Task {
                        scrollToTop = true
                        await feedViewModel.loadInitialVideos()
                        resetUploadForm()
                        onDismiss()
                    }
                }
            }
            .onChange(of: AuthenticationManager.shared.isMarketer) { oldValue, newValue in
                viewModel.checkMarketerStatus()
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
            .split(separator: " ")
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