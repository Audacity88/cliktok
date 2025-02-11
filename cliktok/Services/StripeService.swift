import Foundation
import StripePaymentSheet
import Network
import UIKit

enum StripeError: Error {
    case invalidAmount
    case paymentFailed(String)
    case configurationError
    case networkError(Error)
    case invalidResponse
    case noViewController
    
    var localizedDescription: String {
        switch self {
        case .invalidAmount:
            return "Invalid payment amount"
        case .paymentFailed(let message):
            return "Payment failed: \(message)"
        case .configurationError:
            return "Stripe configuration error"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid server response"
        case .noViewController:
            return "No view controller found"
        }
    }
}

@MainActor
class StripeService {
    static let shared = StripeService()
    private var paymentSheet: PaymentSheet?
    private var currentPaymentIntent: String?
    private let monitor = NWPathMonitor()
    private let monitorQueue = DispatchQueue(label: "com.cliktok.network")
    
    // Backend URL - using localhost for testing
    private var baseURL: String {
        #if targetEnvironment(simulator)
        return "http://127.0.0.1:3000"
        #else
        // Use Mac's IP address when running on physical device
        return "http://192.168.1.69:3000"
        #endif
    }
    
    private init() {
        // Using test key for development
        #if DEBUG
        StripeAPI.defaultPublishableKey = "pk_test_51NTPwxAzsQ4oM3HcZV879oK0QaThw8VYrUze8SWWLybpZUFMzysWUSxdIuyr5BwWR0vLY36r4Af5NgDwXlqZErgL00Mm04xPlM"
        print("StripeService initialized with test key")
        #else
        StripeAPI.defaultPublishableKey = ""
        #endif
        
        print("StripeService initialized with baseURL: \(baseURL)")
        print("StripeService initialized with publishable key: \(StripeAPI.defaultPublishableKey)")
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        monitor.pathUpdateHandler = { [weak self] path in
            DispatchQueue.main.async {
                print("Network status changed: \(path.status)")
                print("Network interface type: \(path.availableInterfaces.map { $0.type })")
                if path.status == .satisfied {
                    print("Network is available")
                } else {
                    print("Network is not available")
                }
            }
        }
        monitor.start(queue: monitorQueue)
    }
    
    private func createURLSession() -> URLSession {
        let config = URLSessionConfiguration.default
        config.waitsForConnectivity = true
        config.timeoutIntervalForResource = 10  // Reduced from 30
        config.timeoutIntervalForRequest = 5    // Reduced from 30
        config.allowsCellularAccess = true
        config.allowsExpensiveNetworkAccess = true
        config.allowsConstrainedNetworkAccess = true
        config.httpMaximumConnectionsPerHost = 1
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.shouldUseExtendedBackgroundIdleMode = true
        
        // Add default headers
        config.httpAdditionalHeaders = [
            "Accept": "*/*",
            "Content-Type": "application/json",
            "Connection": "close"  // Changed from keep-alive to close
        ]
        
        return URLSession(configuration: config)
    }
    
    private func checkServerHealth() async {
        guard let url = URL(string: "\(baseURL)/health") else { return }
        
        let session = createURLSession()
        var request = URLRequest(url: url)
        request.timeoutInterval = 3 // Reduced from 5
        
        do {
            print("\nAttempting server health check at: \(url.absoluteString)")
            let (data, response) = try await session.data(for: request)
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Server health check - Status code: \(httpResponse.statusCode)")
                print("Response headers: \(httpResponse.allHeaderFields)")
                if let responseString = String(data: data, encoding: .utf8) {
                    print("Server health response: \(responseString)")
                }
            }
        } catch {
            print("\nServer health check failed: \(error.localizedDescription)")
            if let urlError = error as? URLError {
                print("Health check URL Error code: \(urlError.code.rawValue)")
                print("Health check URL Error description: \(urlError.localizedDescription)")
                print("Health check URL Error failure URL: \(urlError.failureURLString ?? "none")")
                if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                    print("Underlying error: \(underlyingError)")
                }
            }
        }
    }
    
    deinit {
        monitor.cancel()
    }
    
    func configurePaymentSheet(amount: Double, currency: String = "usd") async throws -> PaymentSheet {
        let amountInCents = Int(amount * 100)
        
        let backendUrl = URL(string: "\(baseURL)/create-payment-intent")!
        var request = URLRequest(url: backendUrl)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = [
            "amount": amountInCents,
            "currency": currency
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        
        // Print the raw response for debugging
        if let responseString = String(data: data, encoding: .utf8) {
            print("Server response: \(responseString)")
        }
        
        guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
              let clientSecret = json["clientSecret"] as? String else {
            throw NSError(domain: "PaymentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }
        
        // Configure payment sheet with minimal test settings
        var configuration = PaymentSheet.Configuration()
        configuration.merchantDisplayName = "ClikTok"
        configuration.returnURL = "cliktok://stripe-redirect"
        
        return PaymentSheet(
            paymentIntentClientSecret: clientSecret,
            configuration: configuration
        )
    }
    
    func handlePaymentResult(_ result: PaymentSheetResult) async throws -> Bool {
        switch result {
        case .completed:
            print("Payment completed successfully")
            return true
            
        case .canceled:
            print("Payment was canceled by user")
            throw StripeError.paymentFailed("Payment was canceled")
            
        case .failed(let error):
            print("Payment failed with error: \(error.localizedDescription)")
            throw StripeError.paymentFailed(error.localizedDescription)
        }
    }
    
    func presentPaymentSheet(_ paymentSheet: PaymentSheet) async throws {
        guard let viewController = UIApplication.shared.keyWindow?.rootViewController else {
            throw NSError(domain: "PaymentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "No view controller found"])
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            paymentSheet.present(from: viewController) { result in
                Task { @MainActor in
                    switch result {
                    case .completed:
                        print("Payment completed!")
                        continuation.resume()
                    case .canceled:
                        print("Payment canceled.")
                        continuation.resume()
                    case .failed(let error):
                        print("Payment failed: \(error.localizedDescription)")
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

// Response model for payment intent creation
struct PaymentIntentResponse: Codable {
    let clientSecret: String
    let paymentIntentId: String
    let publishableKey: String
}

extension UIApplication {
    var keyWindow: UIWindow? {
        return UIApplication.shared.connectedScenes
            .filter { $0.activationState == .foregroundActive }
            .first(where: { $0 is UIWindowScene })
            .flatMap({ $0 as? UIWindowScene })?.windows
            .first(where: \.isKeyWindow)
    }
} 