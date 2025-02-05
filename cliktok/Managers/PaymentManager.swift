import Foundation
import StripePayments
import FirebaseFirestore

@MainActor
class PaymentManager: NSObject, ObservableObject {
    static let shared = PaymentManager()
    
    @Published private(set) var isLoading = false
    @Published private(set) var error: Error?
    
    private let baseURL = "http://localhost:3000"
    private let stripe = StripeAPI.defaultPublishableKey
    
    private override init() {
        super.init()
        StripeAPI.defaultPublishableKey = ProcessInfo.processInfo.environment["STRIPE_PUBLISHABLE_KEY"]
    }
    
    func preparePayment(amount: Double) async throws {
        isLoading = true
        defer { isLoading = false }
        
        do {
            // Create a payment intent
            var request = URLRequest(url: URL(string: "\(baseURL)/create-payment-intent")!)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = ["amount": amount, "currency": "usd"]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            let paymentIntent = try JSONDecoder().decode(PaymentIntentResponse.self, from: data)
            
            // Create payment
            let paymentIntentParams = STPPaymentIntentParams(clientSecret: paymentIntent.clientSecret)
            
            // Present payment methods
            let paymentHandler = STPPaymentHandler.shared()
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                paymentHandler.confirmPayment(paymentIntentParams, with: self) { status, _, error in
                    switch status {
                    case .succeeded:
                        continuation.resume()
                    case .failed:
                        continuation.resume(throwing: error ?? NSError(domain: "Payment", code: 0, userInfo: [NSLocalizedDescriptionKey: "Payment failed"]))
                    case .canceled:
                        continuation.resume(throwing: NSError(domain: "Payment", code: 0, userInfo: [NSLocalizedDescriptionKey: "Payment canceled"]))
                    @unknown default:
                        continuation.resume(throwing: NSError(domain: "Payment", code: 0, userInfo: [NSLocalizedDescriptionKey: "Unknown payment status"]))
                    }
                }
            }
        } catch {
            self.error = error
            throw error
        }
    }
}

extension PaymentManager: STPAuthenticationContext {
    func authenticationPresentingViewController() -> UIViewController {
        // Find the top-most view controller
        guard let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let rootViewController = windowScene.windows.first?.rootViewController else {
            fatalError("No root view controller found")
        }
        return rootViewController
    }
}

private struct PaymentIntentResponse: Codable {
    let clientSecret: String
}
