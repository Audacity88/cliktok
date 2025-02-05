import SwiftUI
import PhotosUI

struct ProfileView: View {
    @StateObject private var viewModel = UserViewModel()
    @State private var isEditing = false
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    
    var body: some View {
        Group {
            if let user = viewModel.currentUser {
                ScrollView {
                    VStack(spacing: 20) {
                        // Profile Image
                        PhotosPicker(selection: $selectedItem, matching: .images) {
                            ZStack {
                                if let imageData = selectedImageData,
                                   let uiImage = UIImage(data: imageData) {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(Circle())
                                } else if let profileURL = user.profileImageURL,
                                          let url = URL(string: profileURL) {
                                    AsyncImage(url: url) { image in
                                        image
                                            .resizable()
                                            .scaledToFill()
                                    } placeholder: {
                                        ProgressView()
                                    }
                                    .frame(width: 100, height: 100)
                                    .clipShape(Circle())
                                } else {
                                    Image(systemName: "person.circle.fill")
                                        .resizable()
                                        .frame(width: 100, height: 100)
                                        .foregroundColor(.gray)
                                }
                                
                                if viewModel.isLoading {
                                    ProgressView()
                                        .frame(width: 100, height: 100)
                                        .background(Color.black.opacity(0.3))
                                        .clipShape(Circle())
                                }
                            }
                        }
                        .overlay(
                            Group {
                                if !viewModel.isLoading {
                                    Circle()
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 2)
                                }
                            }
                        )
                        
                        if isEditing {
                            // Edit Profile Form
                            VStack(spacing: 15) {
                                TextField("Username", text: $username)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                    .autocapitalization(.none)
                                
                                TextField("Display Name", text: $displayName)
                                    .textFieldStyle(RoundedBorderTextFieldStyle())
                                
                                TextEditor(text: $bio)
                                    .frame(height: 100)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                    )
                                
                                Button(action: saveProfile) {
                                    Text("Save Changes")
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(Color.blue)
                                        .foregroundColor(.white)
                                        .cornerRadius(10)
                                }
                            }
                            .padding(.horizontal)
                        } else {
                            // Profile Info
                            VStack(alignment: .leading, spacing: 10) {
                                Text(user.displayName)
                                    .font(.title2)
                                    .bold()
                                
                                Text("@\(user.username)")
                                    .foregroundColor(.gray)
                                
                                if !user.bio.isEmpty {
                                    Text(user.bio)
                                        .padding(.top, 5)
                                }
                                
                                Toggle("Private Account", isOn: Binding(
                                    get: { user.isPrivateAccount },
                                    set: { _ in
                                        Task {
                                            try? await viewModel.togglePrivateAccount()
                                        }
                                    }
                                ))
                                .padding(.top)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                        }
                    }
                }
                .navigationTitle("Profile")
                .navigationBarItems(trailing: Button(isEditing ? "Cancel" : "Edit") {
                    if isEditing {
                        isEditing = false
                    } else {
                        username = user.username
                        displayName = user.displayName
                        bio = user.bio
                        isEditing = true
                    }
                })
            } else {
                ProgressView()
            }
        }
        .task {
            await viewModel.fetchCurrentUser()
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                do {
                    if let data = try? await newItem?.loadTransferable(type: Data.self) {
                        selectedImageData = data
                        if let image = UIImage(data: data) {
                            try await viewModel.uploadProfileImage(image)
                            await viewModel.fetchCurrentUser()
                            selectedImageData = nil
                        }
                    }
                } catch {
                    print("Error uploading profile image: \(error)")
                }
            }
        }
        .alert("Error", isPresented: Binding(
            get: { viewModel.error != nil },
            set: { if !$0 { viewModel.error = nil } }
        )) {
            Button("OK") {
                viewModel.error = nil
            }
        } message: {
            if let error = viewModel.error {
                Text(error.localizedDescription)
            }
        }
    }
    
    private func saveProfile() {
        Task {
            do {
                try await viewModel.updateProfile(
                    username: username,
                    displayName: displayName,
                    bio: bio
                )
                isEditing = false
            } catch {
                print("Error updating profile: \(error)")
            }
        }
    }
}
