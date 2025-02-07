import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var isAnonymous = false
    @Published var isMarketer = false
    
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
                }
            }
        }
    }
    
    private func checkIfMarketer(userId: String) async {
        do {
            let docRef = db.collection("users").document(userId)
            let document = try await docRef.getDocument()
            if let userData = try? document.data(as: User.self) {
                self.isMarketer = userData.userRole == .marketer
            }
        } catch {
            print("Error checking marketer status: \(error)")
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
        
        // Create regular user profile
        let user = User(
            id: result.user.uid,
            username: email.components(separatedBy: "@").first ?? "",
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
        
        // Create marketer user profile
        let user = User(
            id: result.user.uid,
            username: email.components(separatedBy: "@").first ?? "",
            displayName: email.components(separatedBy: "@").first ?? "",
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
        
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
    }
}