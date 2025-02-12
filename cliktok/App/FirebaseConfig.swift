import FirebaseCore
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage
import OSLog
import Network

class FirebaseConfig {
    static let shared = FirebaseConfig()
    private let logger = Logger(component: "FirebaseConfig")
    private var isConfigured = false
    private var connectionAttempts = 0
    private let maxConnectionAttempts = 3
    private let networkMonitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.cliktok.network")
    
    private init() {
        logger.info("🔥 Initializing FirebaseConfig")
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            if path.status == .satisfied {
                self.logger.debug("🌐 Network connection available")
                if !self.isConfigured && self.connectionAttempts < self.maxConnectionAttempts {
                    Task { @MainActor in
                        self.configure()
                    }
                }
            } else {
                self.logger.error("❌ Network connection lost")
            }
        }
        networkMonitor.start(queue: monitorQueue)
    }
    
    func configure() {
        guard !isConfigured else {
            logger.debug("⏭️ Firebase already configured, skipping initialization")
            return
        }
        
        connectionAttempts += 1
        logger.info("🔄 Attempting to configure Firebase (attempt \(self.connectionAttempts))")
        
        do {
            // Configure Firebase
            FirebaseApp.configure()
            logger.debug("🎯 Firebase core configured")
            
            // Configure Firestore with offline persistence
            let db = Firestore.firestore()
            let settings = FirestoreSettings()
            settings.isPersistenceEnabled = true
            settings.cacheSizeBytes = FirestoreCacheSizeUnlimited
            settings.isSSLEnabled = true
            
            // Only use local emulator in DEBUG mode and if explicitly enabled
            #if DEBUG
            if ProcessInfo.processInfo.environment["USE_FIREBASE_EMULATOR"] == "true" {
                do {
                    let host = ProcessInfo.processInfo.environment["FIREBASE_EMULATOR_HOST"] ?? "localhost"
                    try Auth.auth().useEmulator(withHost: host, port: 9099)
                    db.useEmulator(withHost: host, port: 8080)
                    logger.debug("🔧 Using Firebase emulators")
                } catch {
                    logger.error("❌ Failed to configure Firebase emulators: \(error.localizedDescription)")
                }
            }
            #endif
            
            db.settings = settings
            logger.debug("📝 Firestore settings applied")
            
            isConfigured = true
            logger.success("✅ Firebase configured successfully")
            
            // Reset connection attempts on success
            connectionAttempts = 0
            
            // Verify connection with reduced timeout
            let verificationTask = Task {
                do {
                    try await db.collection("_health").document("ping").getDocument(source: .server)
                    logger.success("✅ Firestore connection test successful")
                } catch {
                    logger.error("❌ Firestore connection test failed: \(error.localizedDescription)")
                }
            }
            
            // Add a timeout to the verification
            Task {
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
                verificationTask.cancel()
                logger.debug("⏱️ Connection verification timeout reached")
            }
            
        } catch {
            logger.error("❌ Failed to configure Firebase: \(error.localizedDescription)")
            isConfigured = false
            
            if connectionAttempts < maxConnectionAttempts {
                logger.info("🔄 Will retry configuration later")
            } else {
                logger.error("❌ Max connection attempts reached, giving up")
            }
        }
    }
    
    func checkAuthState() -> AuthState {
        guard isConfigured else {
            logger.error("❌ Firebase not configured")
            return .notConfigured
        }
        
        if let user = Auth.auth().currentUser {
            if user.isAnonymous {
                logger.debug("👤 User is anonymous")
                return .anonymous
            } else {
                logger.debug("👤 User is authenticated")
                return .authenticated
            }
        }
        logger.debug("👤 User is not authenticated")
        return .notAuthenticated
    }
    
    deinit {
        logger.debug("🔥 FirebaseConfig deinitializing")
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
