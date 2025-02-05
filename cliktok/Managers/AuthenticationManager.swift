import Foundation
import FirebaseAuth

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var isAnonymous = false
    
    var currentUser: User? {
        Auth.auth().currentUser
    }
    
    private init() {
        Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.isAuthenticated = user != nil
                self?.userEmail = user?.email
                self?.isAnonymous = user?.isAnonymous ?? false
            }
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
    }
    
    func signUp(email: String, password: String) async throws {
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
    }
    
    func signOut() throws {
        try Auth.auth().signOut()
        self.isAuthenticated = false
        self.userEmail = nil
        self.isAnonymous = false
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