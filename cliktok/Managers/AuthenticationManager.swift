import Foundation
import FirebaseAuth
import FirebaseFirestore
import OSLog

@MainActor
class AuthenticationManager: ObservableObject {
    static let shared = AuthenticationManager()
    private let logger = Logger(component: "AuthenticationManager")
    
    @Published var isAuthenticated = false
    @Published var userEmail: String?
    @Published var isAnonymous = false
    @Published var isMarketer = false {
        didSet {
            if oldValue != self.isMarketer {
                logger.debug("👥 Marketer status changed to: \(self.isMarketer)")
                NotificationCenter.default.post(name: .init("UserRoleChanged"), object: nil)
            }
        }
    }
    
    private let db = Firestore.firestore()
    private var stateListener: AuthStateDidChangeListenerHandle?
    
    var currentUser: FirebaseAuth.User? {
        Auth.auth().currentUser
    }
    
    private init() {
        logger.info("🔐 Initializing AuthenticationManager")
        setupAuthStateListener()
    }
    
    private func setupAuthStateListener() {
        logger.debug("👂 Setting up auth state listener")
        stateListener = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                guard let self = self else { return }
                self.logger.info("🔄 Auth state changed. User: \(user?.uid ?? "nil")")
                
                self.isAuthenticated = user != nil
                self.userEmail = user?.email
                self.isAnonymous = user?.isAnonymous ?? false
                
                if let user = user {
                    await self.checkIfMarketer(userId: user.uid)
                } else {
                    self.isMarketer = false
                }
            }
        }
    }
    
    deinit {
        logger.debug("🔐 AuthenticationManager deinitializing")
        if let listener = stateListener {
            Auth.auth().removeStateDidChangeListener(listener)
        }
    }
    
    private func checkIfMarketer(userId: String) async {
        logger.debug("🔍 Checking marketer status for user: \(userId)")
        do {
            let docSnapshot = try await db.collection("users").document(userId).getDocument()
            if let data = docSnapshot.data(), let userRole = data["userRole"] as? String {
                self.isMarketer = userRole == "marketer"
                logger.debug("👥 User role checked: \(userRole)")
            }
        } catch {
            logger.error("❌ Failed to check marketer status: \(error.localizedDescription)")
            self.isMarketer = false
        }
    }
    
    func signInAnonymously() async throws {
        logger.info("🔑 Attempting anonymous sign in")
        let result = try await Auth.auth().signInAnonymously()
        self.isAuthenticated = true
        self.isAnonymous = true
        logger.success("✅ Signed in anonymously with user ID: \(result.user.uid)")
    }
    
    func signIn(email: String, password: String) async throws {
        logger.info("🔑 Attempting sign in for email: \(email)")
        let result = try await Auth.auth().signIn(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
        await checkIfMarketer(userId: result.user.uid)
        logger.success("✅ Successfully signed in user: \(result.user.uid)")
    }
    
    func signUp(email: String, password: String) async throws {
        logger.info("📝 Attempting to create new user account for: \(email)")
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
        
        let username = "user_\(result.user.uid.prefix(6))"
        logger.debug("👤 Generated username: \(username)")
        
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
        logger.success("✅ Successfully created new user account: \(result.user.uid)")
    }
    
    func signUpAsMarketer(email: String, password: String, companyName: String) async throws {
        logger.info("📝 Attempting to create new marketer account for: \(email)")
        let result = try await Auth.auth().createUser(withEmail: email, password: password)
        self.isAuthenticated = true
        self.userEmail = result.user.email
        self.isAnonymous = false
        self.isMarketer = true
        
        let username = "marketer_\(result.user.uid.prefix(6))"
        logger.debug("👤 Generated marketer username: \(username)")
        
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
        logger.success("✅ Successfully created new marketer account: \(result.user.uid)")
    }
    
    func signOut() throws {
        logger.info("🚪 Attempting to sign out")
        try Auth.auth().signOut()
        self.isAuthenticated = false
        self.userEmail = nil
        self.isAnonymous = false
        self.isMarketer = false
        logger.success("✅ Successfully signed out")
    }
    
    // Convert anonymous account to permanent account
    func convertAnonymousAccount(email: String, password: String) async throws {
        logger.info("🔄 Attempting to convert anonymous account to permanent for: \(email)")
        guard let user = currentUser, user.isAnonymous else {
            logger.error("❌ No anonymous user to convert")
            throw NSError(domain: "AuthError", code: 400, userInfo: [NSLocalizedDescriptionKey: "No anonymous user to convert"])
        }
        
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        let result = try await user.link(with: credential)
        logger.debug("🔗 Successfully linked credential to anonymous account")
        
        // Update user profile with email and username
        let username = "user_\(result.user.uid.prefix(6))"
        logger.debug("👤 Generated username for converted account: \(username)")
        
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
        logger.success("✅ Successfully converted anonymous account to permanent: \(result.user.uid)")
    }
}