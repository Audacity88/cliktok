import SwiftUI
import PhotosUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel = UserViewModel()
    @State private var isEditing = false
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var selectedItem: PhotosPickerItem?
    @State private var selectedImageData: Data?
    
    let userId: String?
    
    init(userId: String? = nil) {
        self.userId = userId
    }
    
    private func checkIsCurrentUser() -> Bool {
        guard let userId = userId else { return true }
        return userId == Auth.auth().currentUser?.uid
    }
    
    var body: some View {
        Group {
            if let user = viewModel.currentUser {
                ProfileContentView(
                    user: user,
                    isCurrentUser: checkIsCurrentUser(),
                    isEditing: .init(get: { isEditing }, set: { isEditing = $0 }),
                    username: .init(get: { username }, set: { username = $0 }),
                    displayName: .init(get: { displayName }, set: { displayName = $0 }),
                    bio: .init(get: { bio }, set: { bio = $0 }),
                    selectedItem: .init(get: { selectedItem }, set: { selectedItem = $0 }),
                    selectedImageData: .init(get: { selectedImageData }, set: { selectedImageData = $0 }),
                    viewModel: viewModel
                )
            } else {
                ProgressView()
            }
        }
        .task {
            if let userId = userId {
                await viewModel.fetchUser(userId: userId)
                await viewModel.fetchUserVideos(for: userId)
            } else {
                await viewModel.fetchCurrentUser()
                await viewModel.fetchUserVideos()
            }
        }
        .onChange(of: selectedItem) { newItem in
            Task {
                if let data = try? await newItem?.loadTransferable(type: Data.self) {
                    selectedImageData = data
                    if let image = UIImage(data: data) {
                        if let url = try? await viewModel.uploadProfileImage(image) {
                            print("Successfully uploaded profile image: \(url)")
                        }
                    }
                }
                selectedItem = nil
            }
        }
    }
}

struct ProfileContentView: View {
    let user: User
    let isCurrentUser: Bool
    @Binding var isEditing: Bool
    @Binding var username: String
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var selectedImageData: Data?
    @ObservedObject var viewModel: UserViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Image
                if isCurrentUser {
                    PhotosPicker(selection: $selectedItem, matching: .images) {
                        ProfileImageView(imageURL: user.profileImageURL, size: 100)
                    }
                } else {
                    ProfileImageView(imageURL: user.profileImageURL, size: 100)
                }
                
                if isEditing {
                    ProfileEditForm(
                        username: $username,
                        displayName: $displayName,
                        bio: $bio,
                        isEditing: $isEditing,
                        viewModel: viewModel
                    )
                } else {
                    ProfileInfoView(
                        user: user,
                        isCurrentUser: isCurrentUser,
                        isEditing: $isEditing,
                        viewModel: viewModel
                    )
                }
                
                // User's Videos Grid
                if !viewModel.userVideos.isEmpty {
                    VideoGridView(videos: viewModel.userVideos, showBackButton: true)
                } else {
                    Text("No videos yet")
                        .foregroundColor(.gray)
                        .padding()
                }
            }
        }
        .navigationTitle(isCurrentUser ? "Profile" : user.displayName)
        .navigationBarItems(trailing: isCurrentUser ? Button(isEditing ? "Cancel" : "Edit") {
            if isEditing {
                isEditing = false
            } else {
                username = user.username
                displayName = user.displayName
                bio = user.bio
                isEditing = true
            }
        } : nil)
    }
}

struct ProfileEditForm: View {
    @Binding var username: String
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var isEditing: Bool
    @ObservedObject var viewModel: UserViewModel
    
    var body: some View {
        VStack(spacing: 16) {
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            TextField("Display Name", text: $displayName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            TextField("Bio", text: $bio)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            Button("Save") {
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
            .buttonStyle(.borderedProminent)
        }
    }
}

struct ProfileInfoView: View {
    let user: User
    let isCurrentUser: Bool
    @Binding var isEditing: Bool
    @ObservedObject var viewModel: UserViewModel
    
    var body: some View {
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
            
            HStack(spacing: 20) {
                VStack {
                    Text("\(viewModel.userVideos.count)")
                        .font(.headline)
                    Text("Videos")
                        .foregroundColor(.gray)
                }
                
                VStack {
                    Text("\(viewModel.userVideos.reduce(0) { $0 + $1.views })")
                        .font(.headline)
                    Text("Views")
                        .foregroundColor(.gray)
                }
            }
            .padding(.top, 10)
            
            if isCurrentUser {
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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
    }
}
