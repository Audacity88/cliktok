import Foundation
import StripePayments
import FirebaseFirestore
import Alamofire
import Network
import SystemConfiguration.CaptiveNetwork

enum PaymentError: LocalizedError {
    case notConfigured
    case serverError(String)
    case networkError(String)
    case invalidResponse
    
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
        }
    }
}

@MainActor
class PaymentManager: NSObject, ObservableObject {
    static let shared = PaymentManager()
    
    @Published private(set) var isLoading = false
    @Published private(set) var error: PaymentError?
    @Published private(set) var isConfigured = false
    
    // Base URL for the server
    private let baseURL = "http://127.0.0.1:3000"  // Use localhost IP instead of hostname
    private var retryCount = 0
    private let maxRetries = 3
    
    private override init() {
        super.init()
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
        let timestamp: String
        let interfaces: [String: [[String: String]]]
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
                                                       headers: headers,
                                                       requestModifier: { urlRequest in
                urlRequest.timeoutInterval = 5
                urlRequest.setValue("127.0.0.1:3000", forHTTPHeaderField: "Host")
            })
            
            // Log cURL command for health check
            healthRequest.cURLDescription { description in
                print("Health check cURL command: \(description)")
            }
            
            do {
                let healthResponse = try await healthRequest.serializingDecodable(HealthResponse.self).value
                print("Server health check response: status=\(healthResponse.status), timestamp=\(healthResponse.timestamp)")
                
                guard healthResponse.status == "ok" else {
                    throw PaymentError.networkError("Server health check failed: \(healthResponse.status)")
                }
            } catch {
                print("Server health check failed: \(error)")
                throw PaymentError.networkError("Server is not running")
            }
            
            print("Fetching Stripe configuration from \(baseURL)/config")
            
            // Create request with timeout using custom session
            let baseRequest = alamofireSession.request("\(baseURL)/config",
                                                     method: .get,
                                                     headers: headers,
                                                     requestModifier: { urlRequest in
                urlRequest.timeoutInterval = 5
                urlRequest.setValue("127.0.0.1:3000", forHTTPHeaderField: "Host")
            })
            
            // Log cURL command before validation chain
            baseRequest.cURLDescription { description in
                print("cURL command: \(description)")
            }
            
            // Create validated request
            let request = baseRequest.validate()
                                   .serializingDecodable(StripeConfig.self)
            
            // Use async/await with timeout
            let response = try await withTimeout(seconds: 30) {
                try await request.value
            }
            
            print("Received response: \(response)")
            StripeAPI.defaultPublishableKey = response.publishableKey
            isConfigured = true
            error = nil
            
        } catch let error as AFError {
            print("Alamofire error: \(error)")
            print("Response code: \(error.responseCode ?? -1)")
            
            switch error {
            case .responseValidationFailed(let reason):
                print("Validation failed: \(reason)")
            case .responseSerializationFailed(let reason):
                print("Serialization failed: \(reason)")
            default:
                print("Other error: \(error)")
            }
            
            print("Underlying error: \(error.underlyingError?.localizedDescription ?? "none")")
            self.error = PaymentError.networkError(error.localizedDescription)
            
            if retryCount < maxRetries {
                retryCount += 1
                print("Retrying Stripe configuration (attempt \(retryCount)/\(maxRetries))...")
                try? await Task.sleep(nanoseconds: UInt64(1_000_000_000 * retryCount))
                await configureStripe()
            }
        } catch {
            print("General error: \(error)")
            self.error = PaymentError.networkError(error.localizedDescription)
            
            if retryCount < maxRetries {
                retryCount += 1
                print("Retrying Stripe configuration (attempt \(retryCount)/\(maxRetries))...")
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
    
    func preparePayment(amount: Double) async throws {
        guard isConfigured else {
            throw PaymentError.notConfigured
        }
        
        isLoading = true
        defer { isLoading = false }
        
        do {
            let headers: HTTPHeaders = [
                .accept("application/json"),
                .contentType("application/json"),
                .userAgent("CliktokApp/1.0")
            ]
            
            let parameters: [String: Any] = ["amount": amount, "currency": "usd"]
            
            let response = try await AF.request("\(baseURL)/create-payment-intent",
                                              method: .post,
                                              parameters: parameters,
                                              encoding: JSONEncoding.default,
                                              headers: headers)
                .serializingDecodable(PaymentIntentResponse.self)
                .value
            
            let paymentIntentParams = STPPaymentIntentParams(clientSecret: response.clientSecret)
            let paymentHandler = STPPaymentHandler.shared()
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                paymentHandler.confirmPayment(paymentIntentParams, with: self) { status, _, error in
                    switch status {
                    case .succeeded:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing: PaymentError.serverError(error?.localizedDescription ?? "Payment failed"))
                    case .canceled:
                        continuation.resume(throwing: PaymentError.serverError("Payment canceled"))
                    @unknown default:
                        continuation.resume(throwing: PaymentError.serverError("Unknown payment status"))
                    }
                }
            }
        } catch {
            let paymentError = error as? PaymentError ?? PaymentError.networkError(error.localizedDescription)
            self.error = paymentError
            throw paymentError
        }
    }
}

// MARK: - Models
private struct PaymentIntentResponse: Codable {
    let clientSecret: String
}

private struct StripeConfig: Codable {
    let publishableKey: String
}

private struct ErrorResponse: Codable {
    let error: String
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
