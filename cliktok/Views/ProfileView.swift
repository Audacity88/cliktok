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
    @State private var showingSignOutAlert = false
    
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
                        do {
                            if let url = try await viewModel.uploadProfileImage(image) {
                                print("Successfully uploaded profile image: \(url)")
                                // Refresh user data to get updated profile image URL
                                if checkIsCurrentUser() {
                                    await viewModel.fetchCurrentUser()
                                } else if let userId = userId {
                                    await viewModel.fetchUser(userId: userId)
                                }
                            }
                        } catch {
                            print("Error uploading profile image: \(error)")
                        }
                    }
                }
                selectedItem = nil
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(action: {
                    showingSignOutAlert = true
                }) {
                    Text("Sign Out")
                        .foregroundColor(.red)
                }
            }
        }
        .alert("Sign Out", isPresented: $showingSignOutAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Sign Out", role: .destructive) {
                Task {
                    try? AuthenticationManager.shared.signOut()
                }
            }
        } message: {
            Text("Are you sure you want to sign out?")
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
                    // Profile Image with PhotosPicker
                    ZStack {
                        if let selectedImageData,
                           let uiImage = UIImage(data: selectedImageData) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else if let profileImageURL = user.profileImageURL,
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
                        
                        if canEdit {
                            PhotosPicker(
                                selection: $selectedItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                Circle()
                                    .fill(Color.black.opacity(0.4))
                                    .frame(width: 100, height: 100)
                                    .overlay(
                                        Image(systemName: "camera.fill")
                                            .foregroundColor(.white)
                                            .font(.system(size: 30))
                                    )
                                    .opacity(0)
                                    .hoverEffect()
                            }
                        }
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
                        displayName = user.displayName
                        bio = user.bio
                        isEditing = true
                    }) {
                        Text("Edit Profile")
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
                    VStack(spacing: 16) {
                        Image(systemName: "film")
                            .font(.system(size: 48))
                            .foregroundColor(.gray)
                        Text("No videos yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        if isCurrentUser {
                            Text("Start sharing your first video!")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: 200)
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
    @State private var username: String = ""
    @State private var showUsernameError = false
    @State private var isMarketer: Bool = false
    @State private var showAlert = false
    @State private var alertMessage = ""
    
    var body: some View {
        VStack(spacing: 16) {
            // Username field with validation
            VStack(alignment: .leading, spacing: 4) {
                TextField("Username", text: $username)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .autocapitalization(.none)
                    .disableAutocorrection(true)
                    .onChange(of: username) { _ in
                        showUsernameError = false
                        viewModel.usernameError = nil
                    }
                    .padding(.horizontal)
                
                if let error = viewModel.usernameError {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.caption)
                        .padding(.horizontal)
                }
            }
            
            TextField(isMarketer ? "Brand/Company Name" : "Display Name", text: $displayName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            TextField("Bio", text: $bio)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)
            
            // Marketer Options
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: $isMarketer) {
                    Label {
                        Text("Brand Account")
                    } icon: {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.blue)
                    }
                }
                .tint(.blue)
                .padding(.horizontal)
            }
            .padding(.vertical, 8)
            
            Button("Save Profile") {
                Task {
                    do {
                        // Only update username if it has changed
                        if username != viewModel.currentUser?.username {
                            try await viewModel.updateUsername(username)
                        }
                        
                        // Update user role if changed
                        let currentIsMarketer = viewModel.currentUser?.userRole == .marketer
                        if isMarketer != currentIsMarketer {
                            try await viewModel.updateUserRole(
                                asMarketer: isMarketer,
                                companyName: isMarketer ? displayName : nil
                            )
                        }
                        
                        // Update other profile fields
                        try await viewModel.updateProfile(
                            displayName: displayName,
                            bio: bio
                        )
                        isEditing = false
                    } catch {
                        if viewModel.usernameError == nil {
                            alertMessage = error.localizedDescription
                            showAlert = true
                        }
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.usernameError != nil || displayName.isEmpty)
            
            Button("Cancel") {
                isEditing = false
            }
            .buttonStyle(.bordered)
        }
        .onAppear {
            // Initialize fields with current values
            username = viewModel.currentUser?.username ?? ""
            isMarketer = viewModel.currentUser?.userRole == .marketer
        }
        .alert("Error", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
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
            // Brand Account Badge for Marketers
            if user.userRole == .marketer {
                HStack {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundColor(.blue)
                    Text("Brand Account")
                        .font(.subheadline)
                        .foregroundColor(.blue)
                }
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            
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
                
                if user.userRole == .marketer {
                    VStack {
                        Text("\(viewModel.userVideos.filter { $0.isAdvertisement ?? false }.count)")
                            .font(.headline)
                        Text("Ads")
                            .foregroundColor(.gray)
                    }
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
