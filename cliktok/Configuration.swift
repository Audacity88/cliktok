import Foundation

enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
        case serverDiscoveryFailed(String)
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = ProcessInfo.processInfo.environment[key] else {
            #if DEBUG
            print("⚠️ Missing configuration value for key: \(key)")
            #endif
            throw Error.missingKey
        }

        guard let value = T(object) else {
            throw Error.invalidValue
        }

        return value
    }

    static func apiKey(for service: String) throws -> String {
        try value(for: service)
    }
    
    // Server configuration
    private static var cachedServerURL: URL?
    private static var serverDiscoveryTask: Task<URL, Swift.Error>?
    
    static var defaultServerPort: Int { 8080 }
    static var defaultServerURLs: [URL] = [
        URL(string: "https://1ff1-24-153-157-38.ngrok-free.app")!,  // ngrok tunnel first
        URL(string: "http://10.10.2.1:\(defaultServerPort)")!  // Mac's en0 interface IP as fallback
    ]
    
    static func getServerURL() async throws -> URL {
        // Return cached URL if available
        if let cached = cachedServerURL {
            return cached
        }
        
        // Cancel any existing discovery task
        serverDiscoveryTask?.cancel()
        
        // Create new discovery task
        let task = Task {
            // Try each URL in order until one works
            for url in defaultServerURLs {
                print("Attempting to connect to server at: \(url)")
                
                // Add a longer timeout for initial connection
                let config = URLSessionConfiguration.default
                config.timeoutIntervalForRequest = 5
                config.timeoutIntervalForResource = 5
                let session = URLSession(configuration: config)
                
                if await isServerReachable(url, using: session) {
                    print("Successfully connected to server at: \(url)")
                    cachedServerURL = url
                    return url
                } else {
                    print("Failed to connect to server at: \(url)")
                }
            }
            
            throw Error.serverDiscoveryFailed("Could not connect to any server")
        }
        
        serverDiscoveryTask = task
        return try await task.value
    }
    
    private static func isServerReachable(_ url: URL, using session: URLSession = .shared) async -> Bool {
        do {
            let healthURL = url.appendingPathComponent("health")
            print("Checking health endpoint: \(healthURL)")
            
            let (_, response) = try await session.data(from: healthURL)
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            print("Health check response status code: \(String(describing: statusCode))")
            
            return statusCode == 200
        } catch {
            print("Health check failed with error: \(error.localizedDescription)")
            return false
        }
    }
}

// MARK: - API Keys
extension Configuration {
    static var openAIApiKey: String {
        get throws {
            try apiKey(for: "OPENAI_API_KEY")
        }
    }
    
    static var stripeSecretKey: String {
        get throws {
            try apiKey(for: "STRIPE_SECRET_KEY")
        }
    }
    
    static var stripePublishableKey: String {
        get throws {
            try apiKey(for: "STRIPE_PUBLISHABLE_KEY")
        }
    }
}

// MARK: - Server Info Types
private struct ServerInfo: Codable {
    struct Address: Codable {
        let interface: String
        let address: String
        let url: String
    }
    
    let addresses: [Address]
    let port: Int
    let mode: String
} 