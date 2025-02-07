import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var isAnonymous = false
    @Published var isMarketer = false {
        didSet {
            if oldValue != isMarketer {
                print("AuthManager: Marketer status changed to: \(isMarketer)")
                NotificationCenter.default.post(name: .init("UserRoleChanged"), object: nil)
            }
        }
    }
    
    private let db = Firestore.firestore()
    
    var currentUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }
    
    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isAuthenticated = user != nil
                self?.userEmail = user?.email
                self?.isAnonymous = user?.isAnonymous ?? false
                if let user = user {
                    await self?.checkIfMarketer(userId: user.uid)
                } else {
                    self?.isMarketer = false
                }
            }
        }
    }
    
    private func checkIfMarketer(userId: String) async {
        do {
            print("AuthManager: Checking marketer status for user: \(userId)")
            let docRef = db.collection("users").document(userId)
            let document = try await docRef.getDocument()
            
            if let data = document.data() {
                print("AuthManager: User data: \(data)")
                let userRole = data["userRole"] as? String
                self.isMarketer = userRole == UserRole.marketer.rawValue
                print("AuthManager: Set marketer status to: \(self.isMarketer)")
            } else {
                print("AuthManager: No user data found")
                self.isMarketer = false
            }
        } catch {
            print("AuthManager: Error checking marketer status: \(error)")
            self.isMarketer = false
        }
    }
    
    func signInAnonymously() async throws {
        let result = try await Auth.auth().signInAnonymously()
        self.isAuthenticated = true
        self.isAnonymous = true
        print("Signed in anonymously with user ID: \(result.user.uid)")
    }
    
    func signIn(email: String, password: String) async throws {
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
        await checkIfMarketer(userId: result.user.uid)
    }
    
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
        
        let username = "user_\(result.user.uid.prefix(6))"
        
        // Create regular user profile
        let user = User(
            id: result.user.uid,
            email: email,
            username: username,
            displayName: email.components(separatedBy: "@").first ?? "",
            bio: "",
            userRole: .regular
        )
        
        try await db.collection("users").document(result.user.uid).setData(from: user)
    }
    
    func signUpAsMarketer(email: String, password: String, companyName: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
        self.isMarketer = true
        
        let username = "marketer_\(result.user.uid.prefix(6))"
        
        // Create marketer user profile
        let user = User(
            id: result.user.uid,
            email: email,
            username: username,
            displayName: companyName,
            bio: "",
            userRole: .marketer,
            companyName: companyName
        )
        
        try await db.collection("users").document(result.user.uid).setData(from: user)
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        self.isAuthenticated = false
        self.userEmail = nil
        self.isAnonymous = false
        self.isMarketer = false
    }
    
    // Convert anonymous account to permanent account
    func convertAnonymousAccount(email: String, password: String) async throws {
        guard let user = currentUser, user.isAnonymous else {
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "No anonymous user to convert"])
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await user.link(with: credential)
        
        // Update user profile with email and username
        let username = "user_\(result.user.uid.prefix(6))"
        let userProfile = User(
            id: result.user.uid,
            email: email,
            username: username,
            displayName: email.components(separatedBy: "@").first ?? "",
            bio: "",
            userRole: .regular
        )
        
        try await db.collection("users").document(result.user.uid).setData(from: userProfile)
        
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
    }
}