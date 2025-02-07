import Foundation
import StripePaymentSheet
import FirebaseFirestore
import Alamofire
import Network
import SystemConfiguration.CaptiveNetwork

enum PaymentError: LocalizedError {
    case notConfigured
    case serverError(String)
    case networkError(String)
    case invalidResponse
    case insufficientFunds
    case invalidURL
    
    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Payment system not configured. Please check server configuration."
        case .serverError(let message):
            return "Server error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid server response"
        case .insufficientFunds:
            return "Insufficient funds"
        case .invalidURL:
            return "Invalid URL"
        }
    }
}

@MainActor
class PaymentManager: NSObject, ObservableObject {
    static let shared = PaymentManager()
    
    @Published private(set) var isLoading = false
    @Published private(set) var error: PaymentError?
    @Published private(set) var isConfigured = false
    @Published private(set) var isTestMode = false
    
    // Base URL for the server
    #if DEBUG
    private let baseURL = ProcessInfo.processInfo.environment["STRIPE_API_URL"] ?? "http://127.0.0.1:3000"
    #else
    private let baseURL = ProcessInfo.processInfo.environment["STRIPE_API_URL"] ?? "https://api.cliktok.com"
    #endif
    
    private var retryCount = 0
    private let maxRetries = 3
    
    // MARK: - Development Mode
    
    private let defaults = UserDefaults.standard
    private let isDevelopmentModeKey = "com.cliktok.isDevelopmentMode"
    
    @Published private(set) var isDevelopmentMode: Bool {
        didSet {
            defaults.set(isDevelopmentMode, forKey: isDevelopmentModeKey)
        }
    }
    
    private var currentBalance: Decimal = 0.0
    
    private override init() {
        // Load development mode state
        self.isDevelopmentMode = defaults.bool(forKey: isDevelopmentModeKey)
        self.isTestMode = false
        
        // Initialize balance to 0
        self.currentBalance = 0
        
        super.init()
        
        // Load saved balance
        let savedBalance = defaults.double(forKey: "userBalance")
        self.currentBalance = Decimal(savedBalance)
        
        // Always configure server connection first
        configureServerConnection()
        
        print("PaymentManager initialized - checking server configuration...")
    }
    
    private func configureServerConnection() {
        print("Initializing PaymentManager with baseURL: \(baseURL)")
        
        // Configure Alamofire for development
        #if DEBUG
        let evaluators: [String: ServerTrustEvaluating] = [
            "127.0.0.1": DisabledTrustEvaluating(),
            "localhost": DisabledTrustEvaluating()
        ]
        
        let manager = ServerTrustManager(evaluators: evaluators)
        let configuration = URLSessionConfiguration.default
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 300
        configuration.waitsForConnectivity = true
        
        // Configure for IPv4
        let headers: HTTPHeaders = [
            .accept("application/json"),
            .contentType("application/json"),
            .userAgent("CliktokApp/1.0")
        ]
        
        // Convert HTTPHeaders to URLSession headers dictionary
        let sessionHeaders: [AnyHashable: Any] = [
            "Accept": "application/json",
            "Content-Type": "application/json",
            "User-Agent": "CliktokApp/1.0"
        ]
        configuration.httpAdditionalHeaders = sessionHeaders
        
        // Set up event monitors
        let monitors: [EventMonitor] = [NetworkEventMonitor()]
        
        // Create custom Alamofire instance with IPv4 configuration
        let customAF = Session(
            configuration: configuration,
            serverTrustManager: manager,
            eventMonitors: monitors
        )
        
        // Store the custom session for later use
        self.alamofireSession = customAF
        
        // Configure network monitoring for localhost
        let monitor = NWPathMonitor(requiredInterfaceType: .loopback)
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }
            
            print("Network path update:")
            print("Status: \(path.status)")
            print("Available interfaces: \(path.availableInterfaces.map { $0.name })")
            print("Is expensive: \(path.isExpensive)")
            print("Supports IPv4: \(path.supportsIPv4)")
            print("Supports IPv6: \(path.supportsIPv6)")
            
            if path.status == .satisfied {
                print("Network path is satisfied")
                Task { @MainActor in
                    if !self.isConfigured {
                        await self.configureStripe()
                    }
                }
            } else {
                print("Network path is not satisfied")
                Task { @MainActor in
                    self.error = PaymentError.networkError("Network path not satisfied")
                }
            }
        }
        
        let queue = DispatchQueue(label: "com.cliktok.network.monitor")
        monitor.start(queue: queue)
        
        // Log network settings
        if let proxySettings = CFNetworkCopySystemProxySettings()?.takeUnretainedValue() as? [String: Any] {
            print("Network settings:")
            proxySettings.forEach { key, value in
                print("\(key): \(value)")
            }
        }
        #endif
        
        Task {
            await configureStripe()
        }
    }
    
    // Store custom Alamofire session
    private var alamofireSession: Session!
    
    // Custom event monitor for logging network requests
    private class NetworkEventMonitor: EventMonitor {
        func requestDidResume(_ request: Request) {
            print("Request started: \(request)")
            request.cURLDescription { description in
                print("cURL command: \(description)")
            }
        }
        
        func request<Value>(_ request: DataRequest, didParseResponse response: DataResponse<Value, AFError>) {
            print("Response received for \(request)")
            if let error = response.error {
                print("Error: \(error)")
            }
            if let data = response.data, let str = String(data: data, encoding: .utf8) {
                print("Response data: \(str)")
            }
        }
    }
    
    @MainActor
    private func getIPv4Address(for interfaceName: String) async throws -> String? {
        var address: String?
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            throw NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get network interfaces"])
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            
            // Check if the interface name matches
            let name = String(cString: (interface?.ifa_name)!)
            guard name == interfaceName else { continue }
            
            // Check if it's IPv4
            let family = interface?.ifa_addr.pointee.sa_family
            guard family == UInt8(AF_INET) else { continue }
            
            // Convert interface address to a string
            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface?.ifa_addr,
                       socklen_t((interface?.ifa_addr.pointee.sa_len)!),
                       &hostname,
                       socklen_t(hostname.count),
                       nil,
                       0,
                       NI_NUMERICHOST)
            
            address = String(cString: hostname)
            break
        }
        
        return address
    }
    
    private struct HealthResponse: Codable {
        let status: String
        let mode: String
    }
    
    private func configureStripe() async {
        guard !isConfigured else { return }
        
        do {
            let headers: HTTPHeaders = [
                .accept("application/json"),
                .contentType("application/json"),
                .userAgent("CliktokApp/1.0")
            ]
            
            // First check if server is running
            print("Checking server health at \(baseURL)/health")
            let healthRequest = alamofireSession.request("\(baseURL)/health",
                                                       method: .get,
                                                       headers: headers)
            
            do {
                let healthResponse = try await healthRequest.serializingDecodable(HealthResponse.self).value
                print("Server health check response: status=\(healthResponse.status), mode=\(healthResponse.mode)")
                
                guard healthResponse.status == "ok" else {
                    throw PaymentError.networkError("Server health check failed: \(healthResponse.status)")
                }
                
                // If server is in test mode, disable development mode
                if healthResponse.mode == "test" {
                    print("Server is in test mode - disabling development mode")
                    isDevelopmentMode = false
                    defaults.set(false, forKey: isDevelopmentModeKey)
                    defaults.set(false, forKey: "didSetInitialDevelopmentMode")
                }
            } catch {
                print("Server health check failed: \(error)")
                throw PaymentError.networkError("Server is not running")
            }
            
            print("Fetching Stripe configuration from \(baseURL)/config")
            
            // Create request with timeout using custom session
            let request = alamofireSession.request("\(baseURL)/config",
                                                 method: .get,
                                                 headers: headers)
                .validate()
                .serializingDecodable(StripeConfig.self)
            
            // Use async/await with timeout
            let config = try await withTimeout(seconds: 30) {
                try await request.value
            }
            
            print("Received config: mode=\(config.mode), isTestMode=\(config.isTestMode)")
            StripeAPI.defaultPublishableKey = config.publishableKey
            isTestMode = config.isTestMode
            
            // If server is in test mode, ensure development mode is disabled
            if isTestMode {
                print("Stripe config confirms test mode - ensuring development mode is disabled")
                isDevelopmentMode = false
                defaults.set(false, forKey: isDevelopmentModeKey)
                defaults.set(false, forKey: "didSetInitialDevelopmentMode")
            }
            
            isConfigured = true
            error = nil
            
            print("Payment configuration complete - Mode: \(isTestMode ? "Test" : (isDevelopmentMode ? "Development" : "Production"))")
            
        } catch let error as AFError {
            print("Alamofire error: \(error)")
            self.error = PaymentError.networkError(error.localizedDescription)
            retryConfiguration()
        } catch {
            print("General error: \(error)")
            self.error = PaymentError.networkError(error.localizedDescription)
            retryConfiguration()
        }
    }
    
    private func retryConfiguration() {
        if retryCount < maxRetries {
            retryCount += 1
            print("Retrying Stripe configuration (attempt \(retryCount)/\(maxRetries))...")
            Task {
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * retryCount))
                await configureStripe()
            }
        }
    }
    
    private func withTimeout<T>(seconds: TimeInterval, operation: @escaping () async throws -> T) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask {
                try await operation()
            }
            
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw PaymentError.networkError("Operation timed out after \(seconds) seconds")
            }
            
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }
    
    private func getNetworkInterfaces() throws -> [String] {
        var interfaces: [String] = []
        
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0 else {
            throw NSError(domain: "NetworkError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to get network interfaces"])
        }
        defer { freeifaddrs(ifaddr) }
        
        var ptr = ifaddr
        while ptr != nil {
            defer { ptr = ptr?.pointee.ifa_next }
            
            let interface = ptr?.pointee
            let addrFamily = interface?.ifa_addr.pointee.sa_family
            
            if addrFamily == UInt8(AF_INET) {
                let name = String(cString: (interface?.ifa_name)!)
                interfaces.append(name)
            }
        }
        
        return interfaces
    }
    
    @MainActor
    func createPaymentIntent(amount: Int) async throws -> PaymentSheet {
        if isDevelopmentMode {
            throw PaymentError.notConfigured
        }
        
        guard isConfigured else {
            throw PaymentError.notConfigured
        }
        
        guard let url = URL(string: "\(baseURL)/create-payment-intent") else {
            throw PaymentError.invalidURL
        }
        
        isLoading = true
        defer { isLoading = false }
        
        let parameters: Parameters = [
            "amount": amount,
            "currency": "usd"
        ]
        
        let headers: HTTPHeaders = [
            .accept("application/json"),
            .contentType("application/json"),
            .userAgent("CliktokApp/1.0")
        ]
        
        do {
            let response = try await alamofireSession.request(url,
                                                            method: .post,
                                                            parameters: parameters,
                                                            encoding: JSONEncoding.default,
                                                            headers: headers)
                .serializingDecodable(CreatePaymentIntentResponse.self)
                .value
            
            // Initialize the PaymentSheet
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "CliktTok"
            configuration.allowsDelayedPaymentMethods = false
            configuration.returnURL = "cliktok://stripe-redirect"
            
            let paymentSheet = PaymentSheet(
                paymentIntentClientSecret: response.clientSecret,
                configuration: configuration
            )
            
            return paymentSheet
        } catch {
            print("Payment intent creation failed: \(error)")
            throw PaymentError.serverError(error.localizedDescription)
        }
    }
    
    // MARK: - Public Interface
    
    func addTestMoney(amount: Decimal) {
        guard isDevelopmentMode else {
            print("Cannot add test money in production mode")
            return
        }
        
        addBalance(amount: amount)
        print("Added \(amount) test money. New balance: \(currentBalance)")
    }
    
    func addBalance(amount: Decimal) {
        currentBalance += amount
        UserDefaults.standard.set(NSDecimalNumber(decimal: currentBalance).doubleValue, forKey: "userBalance")
    }
    
    func useBalance(amount: Decimal) -> Bool {
        guard amount <= currentBalance else {
            return false
        }
        currentBalance -= amount
        UserDefaults.standard.set(NSDecimalNumber(decimal: currentBalance).doubleValue, forKey: "userBalance")
        return true
    }
    
    func getCurrentBalance() -> Decimal {
        return currentBalance
    }
    
    func loadBalance() {
        let savedBalance = UserDefaults.standard.double(forKey: "userBalance")
        currentBalance = Decimal(savedBalance)
    }
    
    func toggleDevelopmentMode() {
        isDevelopmentMode.toggle()
        print("Switched to \(isDevelopmentMode ? "development" : "production") mode")
    }
    
    func clearPaymentData() {
        // Clear all payment-related UserDefaults
        defaults.removeObject(forKey: isDevelopmentModeKey)
        defaults.removeObject(forKey: "didSetInitialDevelopmentMode")
        defaults.removeObject(forKey: "userBalance")
        
        // Reset local state
        isDevelopmentMode = false
        isTestMode = false
        currentBalance = 0
        
        print("Cleared all payment data from UserDefaults")
        
        // Reconfigure payment system
        Task {
            await configureStripe()
        }
    }
    
    // MARK: - Helper Functions
    
    private func formatCurrency(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        return formatter.string(from: NSDecimalNumber(decimal: amount)) ?? "$\(amount)"
    }
}

// MARK: - Models
private struct PaymentIntentResponse: Codable {
    let clientSecret: String
}

private struct StripeConfig: Codable {
    let publishableKey: String
    let mode: String
    let isTestMode: Bool
}

private struct ErrorResponse: Codable {
    let error: String
}

private struct CreatePaymentIntentResponse: Codable {
    let clientSecret: String
}

// MARK: - STPAuthenticationContext
extension PaymentManager: STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        let scenes = UIApplication.shared.connectedScenes
        let windowScene = scenes.first as? UIWindowScene
        let window = windowScene?.windows.first
        return window?.rootViewController?.topMostViewController() ?? UIViewController()
    }
}

// MARK: - Array Extension
private extension Array {
    subscript(safe index: Int) -> Element? {
        return indices.contains(index) ? self[index] : nil
    }
}

// MARK: - Network Logger
class NetworkLogger {
    static let shared = NetworkLogger()
    
    private init() {}
    
    func startLogging() {
        #if DEBUG
        let networkLogger = NetworkLogger()
        let configuration = URLSessionConfiguration.default
        configuration.protocolClasses = [LoggingURLProtocol.self]
        #endif
    }
}

class LoggingURLProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool {
        return true
    }
    
    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        return request
    }
    
    override func startLoading() {
        if let url = request.url?.absoluteString {
            print("🌐 Request: \(url)")
            print("📤 Headers: \(request.allHTTPHeaderFields ?? [:])")
            if let body = request.httpBody {
                print("📦 Body: \(String(data: body, encoding: .utf8) ?? "")")
            }
        }
        
        if let client = client {
            client.urlProtocol(self, didFailWithError: NSError(domain: "", code: -1, userInfo: nil))
        }
    }
    
    override func stopLoading() {}
}

// MARK: - Custom Trust Evaluator for Development
#if DEBUG
class DisabledTrustEvaluating: ServerTrustEvaluating {
    func evaluate(_ trust: SecTrust, forHost host: String) throws {
        print("🔒 Allowing connection to host: \(host)")
    }
}
#endif
