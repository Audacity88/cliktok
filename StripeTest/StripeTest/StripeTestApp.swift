//
//  StripeTestApp.swift
//  StripeTest
//
//  Created by Daniel Gilles on 2/11/25.
//

import SwiftUI
import StripePaymentSheet
import UIKit

struct PaymentIntent: Decodable {
    let clientSecret: String
}

@main
struct StripeTestApp: App {
    init() {
        // Initialize the Stripe SDK with your publishable key
        StripeAPI.defaultPublishableKey = "pk_test_51NTPwxAzsQ4oM3HcZV879oK0QaThw8VYrUze8SWWLybpZUFMzysWUSxdIuyr5BwWR0vLY36r4Af5NgDwXlqZErgL00Mm04xPlM"
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .onOpenURL { url in
                    if url.scheme == "stripesdk" {
                        StripeAPI.handleURLCallback(with: url)
                    }
                }
        }
    }
}

struct ContentView: View {
    @State private var paymentResult: PaymentSheetResult?
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            Button(isLoading ? "Loading..." : "Pay") {
                Task {
                    await handlePayment()
                }
            }
            .disabled(isLoading)
            
            if let result = paymentResult {
                switch result {
                case .completed:
                    Text("Payment completed!")
                        .foregroundColor(.green)
                case .canceled:
                    Text("Payment canceled.")
                        .foregroundColor(.orange)
                case .failed(let error):
                    Text("Payment failed: \(error.localizedDescription)")
                        .foregroundColor(.red)
                }
            }
        }
        .padding()
    }
    
    func handlePayment() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let backendUrl = URL(string: "http://192.168.1.69:3000/create-payment-intent")!
            
            var request = URLRequest(url: backendUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "amount": 1000,
                "currency": "usd"
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
            
            // These are optional, only use them if provided by the server
            let customerId = json["customer"] as? String
            let customerEphemeralKeySecret = json["ephemeralKey"] as? String
            let publishableKey = json["publishableKey"] as? String
            
            if let publishableKey = publishableKey {
                StripeAPI.defaultPublishableKey = publishableKey
            }
            
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "StripeTest"
            if let customerId = customerId,
               let customerEphemeralKeySecret = customerEphemeralKeySecret {
                configuration.customer = .init(id: customerId, ephemeralKeySecret: customerEphemeralKeySecret)
            }
            configuration.returnURL = "stripesdk://payment-complete"
            
            let paymentSheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: configuration)
            
            await handlePaymentSheet(paymentSheet)
            
        } catch {
            print("Error: \(error)")
            await MainActor.run {
                paymentResult = .failed(error: error)
            }
        }
    }
    
    @MainActor
    func handlePaymentSheet(_ paymentSheet: PaymentSheet) async {
        do {
            guard let viewController = UIApplication.shared.keyWindow?.rootViewController else {
                print("No view controller found")
                return
            }
            
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                paymentSheet.present(from: viewController) { result in
                    Task { @MainActor in
                        self.paymentResult = result
                        
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
        } catch {
            print("Failed to present PaymentSheet: \(error)")
            self.paymentResult = .failed(error: error)
        }
    }
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
