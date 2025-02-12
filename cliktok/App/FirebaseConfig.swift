import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import OSLog
import Network

class FirebaseConfig {
    static let shared = FirebaseConfig()
    private let logger = Logger(subsystem: "gauntletai.cliktok", category: "FirebaseConfig")
    private var isConfigured = false
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.cliktok.network")
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                self.logger.debug("Network connection available")
                if !self.isConfigured {
                    Task { @MainActor in
                        self.configure()
                    }
                }
            } else {
                self.logger.error("Network connection lost")
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    func configure() {
        guard !isConfigured else {
            logger.debug("Firebase already configured, skipping initialization")
            return
        }
        
        do {
            // Configure Firebase
            FirebaseApp.configure()
            
            // Configure Firestore with offline persistence
            let db = Firestore.firestore()
            let settings = FirestoreSettings()
            settings.isPersistenceEnabled = true
            settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
            settings.isSSLEnabled = true
            db.settings = settings
            
            // Enable offline persistence for Auth
            #if DEBUG
            do {
                try Auth.auth().useEmulator(withHost: "localhost", port: 9099)
                logger.debug("Using Auth emulator")
            } catch {
                logger.error("Failed to configure Auth emulator: \(error.localizedDescription)")
            }
            #endif
            
            isConfigured = true
            logger.debug("✅ Firebase configured successfully")
            
            // Verify connection
            db.collection("_health").document("ping").getDocument { [weak self] (document, error) in
                if let error = error {
                    self?.logger.error("❌ Firestore connection test failed: \(error.localizedDescription)")
                } else {
                    self?.logger.debug("✅ Firestore connection test successful")
                }
            }
            
        } catch {
            logger.error("❌ Failed to configure Firebase: \(error.localizedDescription)")
            // Reset configuration flag to allow retry
            isConfigured = false
        }
    }
    
    func checkAuthState() -> AuthState {
        guard isConfigured else {
            logger.error("Firebase not configured")
            return .notConfigured
        }
        
        if let user = Auth.auth().currentUser {
            if user.isAnonymous {
                return .anonymous
            } else {
                return .authenticated
            }
        }
        return .notAuthenticated
    }
    
    deinit {
        networkMonitor.cancel()
    }
}

enum AuthState: CustomStringConvertible {
    case notConfigured
    case notAuthenticated
    case authenticated
    case anonymous
    
    var description: String {
        switch self {
        case .notConfigured: return "Not Configured"
        case .notAuthenticated: return "Not Authenticated"
        case .authenticated: return "Authenticated"
        case .anonymous: return "Anonymous"
        }
    }
} 