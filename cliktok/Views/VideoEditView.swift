import SwiftUI

struct VideoEditView: View {
    let video: Video
    @Binding var isPresented: Bool
    @EnvironmentObject private var feedViewModel: VideoFeedViewModel
    @State private var caption: String
    @State private var hashtags: String
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var showDeleteConfirmation = false
    @State private var isLoading = false
    
    init(video: Video, isPresented: Binding<Bool>) {
        self.video = video
        self._isPresented = isPresented
        _caption = State(initialValue: video.caption)
        _hashtags = State(initialValue: video.hashtags.joined(separator: " "))
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Video Details")) {
                    TextField("Caption", text: $caption)
                    HashtagTextField(text: $hashtags, placeholder: "Enter hashtags")
                }
                
                Section {
                    Button(action: {
                        showDeleteConfirmation = true
                    }) {
                        HStack {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                            Text("Delete Video")
                                .foregroundColor(.red)
                        }
                    }
                }
            }
            .navigationTitle("Edit Video")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        Task {
                            await saveChanges()
                        }
                    }
                    .disabled(isLoading)
                }
            }
            .alert("Error", isPresented: $showAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .alert("Delete Video", isPresented: $showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    Task {
                        await deleteVideo()
                    }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Are you sure you want to delete this video? This action cannot be undone.")
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))
                }
            }
        }
        .presentationDetents([.medium])
    }
    
    private func saveChanges() async {
        isLoading = true
        
        let hashtagArray = hashtags
            .split(separator: " ")
            .map { String($0).trimmingCharacters(in: .whitespaces).lowercased() }
            .filter { !$0.isEmpty }
            .map { $0.hasPrefix("#") ? String($0.dropFirst()) : $0 }
        
        print("Saving hashtags: \(hashtagArray)")
        
        do {
            try await feedViewModel.updateVideo(video, caption: caption, hashtags: hashtagArray)
            isPresented = false
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
        
        isLoading = false
    }
    
    private func deleteVideo() async {
        isLoading = true
        
        do {
            try await feedViewModel.deleteVideo(video)
            isPresented = false
        } catch {
            alertMessage = error.localizedDescription
            showAlert = true
        }
        
        isLoading = false
    }
} 