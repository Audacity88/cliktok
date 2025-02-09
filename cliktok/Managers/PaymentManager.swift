import Foundation
import FirebaseFirestore
import Network

enum PaymentError: Error {
    case notConfigured
    case invalidURL
    case serverError(String)
    case insufficientFunds
    case networkError
}

class PaymentManager {
    static let shared = PaymentManager()
    
    // MARK: - Properties
    @Published private(set) var isConfigured = false
    @Published private(set) var isLoading = false
    @Published private(set) var isDevelopmentMode = false
    @Published private(set) var isTestMode = false
    
    private let baseURL = "https://api.cliktok.app"
    private let db = Firestore.firestore()
    private let networkMonitor = NWPathMonitor()
    private let userDefaults = UserDefaults.standard
    private var isNetworkAvailable = true
    
    private init() {
        setupNetworkMonitoring()
    }
    
    private func setupNetworkMonitoring() {
        networkMonitor.pathUpdateHandler = { [weak self] path in
            self?.isNetworkAvailable = path.status == .satisfied
        }
        networkMonitor.start(queue: DispatchQueue.global())
    }
    
    // MARK: - Development Mode
    
    func enableDevelopmentMode() {
        isDevelopmentMode = true
        isTestMode = true
        isConfigured = true
    }
    
    func disableDevelopmentMode() {
        isDevelopmentMode = false
        isTestMode = false
        isConfigured = false
    }
    
    func addTestMoney(amount: Decimal) {
        guard isDevelopmentMode else { return }
        let key = "dev_balance"
        let currentBalance = userDefaults.double(forKey: key)
        userDefaults.set(currentBalance + NSDecimalNumber(decimal: amount).doubleValue, forKey: key)
    }
    
    func getTestBalance() -> Double {
        guard isDevelopmentMode else { return 0 }
        return userDefaults.double(forKey: "dev_balance")
    }
    
    // MARK: - Configuration
    
    @MainActor
    func configure() async throws {
        guard !isDevelopmentMode else {
            isConfigured = true
            return
        }
        
        guard isNetworkAvailable else {
            throw PaymentError.networkError
        }
        
        guard let url = URL(string: "\(baseURL)/health") else {
            throw PaymentError.invalidURL
        }
        
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                throw PaymentError.serverError("Invalid response")
            }
            
            guard httpResponse.statusCode == 200 else {
                throw PaymentError.serverError("Server returned status code \(httpResponse.statusCode)")
            }
            
            let config = try JSONDecoder().decode(StripeConfig.self, from: data)
            isTestMode = config.isTestMode
            isConfigured = true
            
        } catch {
            throw PaymentError.serverError(error.localizedDescription)
        }
    }
    
    // MARK: - Payment Processing
    
    @MainActor
    func processPayment(amount: Double, completion: @escaping (Bool, String?) -> Void) {
        // TODO: Implement payment processing
        completion(true, nil)
    }
}

// MARK: - Models
private struct HealthResponse: Codable {
    let status: String
    let mode: String
}

private struct StripeConfig: Codable {
    let mode: String
    let isTestMode: Bool
}

private struct ErrorResponse: Codable {
    let error: String
}

// MARK: - Array Extension
private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
