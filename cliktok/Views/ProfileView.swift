import SwiftUI
import PhotosUI
import FirebaseAuth

struct ProfileView: View {
    @StateObject private var viewModel = UserViewModel()
    @StateObject private var feedViewModel = VideoFeedViewModel()
    @State private var isEditing = false
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
    
    private var canEdit: Bool {
        checkIsCurrentUser() && Auth.auth().currentUser?.isAnonymous != true
    }
    
    private var isViewingOwnProfileAsGuest: Bool {
        checkIsCurrentUser() && Auth.auth().currentUser?.isAnonymous == true
    }
    
    var body: some View {
        Group {
            if isViewingOwnProfileAsGuest {
                GuestProfileView()
            } else if let user = checkIsCurrentUser() ? viewModel.currentUser : viewModel.viewedUser {
                if isEditing && !canEdit {
                    GuestRestrictedView()
                } else {
                    ProfileContentView(
                        user: user,
                        isCurrentUser: checkIsCurrentUser(),
                        canEdit: canEdit,
                        isEditing: .init(get: { isEditing }, set: { isEditing = $0 }),
                        displayName: .init(get: { displayName }, set: { displayName = $0 }),
                        bio: .init(get: { bio }, set: { bio = $0 }),
                        selectedItem: .init(get: { selectedItem }, set: { selectedItem = $0 }),
                        selectedImageData: .init(get: { selectedImageData }, set: { selectedImageData = $0 }),
                        viewModel: viewModel
                    )
                    .environmentObject(feedViewModel)
                }
            } else {
                ProgressView()
            }
        }
        .task {
            // Fetch user data if viewing someone else's profile or if not an anonymous user
            if !isViewingOwnProfileAsGuest {
                if let userId = userId {
                    await viewModel.fetchUser(userId: userId)
                    await viewModel.fetchUserVideos(for: userId)
                } else {
                    await viewModel.fetchCurrentUser()
                    await viewModel.fetchUserVideos()
                }
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

struct GuestProfileView: View {
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.fill")
                .resizable()
                .frame(width: 100, height: 100)
                .foregroundColor(.gray)
            
            Text("Guest User")
                .font(.title2)
                .bold()
            
            Text("Create an account to access all features")
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            Button(action: {
                try? AuthenticationManager.shared.signOut()
            }) {
                Text("Sign Out")
                    .foregroundColor(.red)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            
            Spacer()
        }
        .padding(.top, 50)
        .navigationTitle("Profile")
    }
}

struct ProfileContentView: View {
    let user: User
    let isCurrentUser: Bool
    let canEdit: Bool
    @Binding var isEditing: Bool
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var selectedItem: PhotosPickerItem?
    @Binding var selectedImageData: Data?
    @ObservedObject var viewModel: UserViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // Profile Header
                VStack(spacing: 16) {
                    // Profile Image
                    if let profileImageURL = user.profileImageURL,
                       let url = URL(string: profileImageURL) {
                        AsyncImage(url: url) { image in
                            image
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .frame(width: 100, height: 100)
                        }
                    } else {
                        Circle()
                            .fill(Color.gray.opacity(0.3))
                            .frame(width: 100, height: 100)
                            .overlay(
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 60, height: 60)
                                    .foregroundColor(.gray)
                            )
                    }
                    
                    if isEditing {
                        ProfileEditForm(
                            displayName: $displayName,
                            bio: $bio,
                            isEditing: $isEditing,
                            viewModel: viewModel
                        )
                    } else {
                        // User Info
                        VStack(spacing: 8) {
                            Text(user.username)
                                .font(.title2)
                                .fontWeight(.bold)
                            
                            if !user.displayName.isEmpty && user.displayName != user.username {
                                Text(user.displayName)
                                    .font(.headline)
                            }
                            
                            if !user.bio.isEmpty {
                                Text(user.bio)
                                    .font(.body)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    }
                }
                .padding()
                
                // Edit Profile Button
                if canEdit && !isEditing {
                    Button(action: {
                        if isEditing {
                            isEditing = false
                        } else {
                            displayName = user.displayName
                            bio = user.bio
                            isEditing = true
                        }
                    }) {
                        Text(isEditing ? "Cancel" : "Edit Profile")
                            .foregroundColor(.white)
                            .frame(width: 200)
                            .padding()
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                }
                
                // Videos Grid
                if !viewModel.userVideos.isEmpty {
                    VideoGridView(videos: viewModel.userVideos, showBackButton: false)
                } else {
                    ProgressView()
                        .padding()
                }
            }
        }
    }
}

struct ProfileEditForm: View {
    @Binding var displayName: String
    @Binding var bio: String
    @Binding var isEditing: Bool
    @ObservedObject var viewModel: UserViewModel
    
    var body: some View {
        VStack(spacing: 16) {
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
    let canEdit: Bool
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
            
            if canEdit {
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
