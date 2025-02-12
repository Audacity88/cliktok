import SwiftUI
import FirebaseFirestore
import Foundation
import StripePaymentSheet

// Add these types before the TipViewModel class
private struct StripeConfig: Codable {
    let publishableKey: String
    let mode: String
    let isTestMode: Bool
}

private struct StripePaymentIntentResponse: Codable {
    let clientSecret: String
    let paymentIntentId: String
    let publishableKey: String
}

@MainActor
class TipViewModel: ObservableObject {
    static let shared = TipViewModel()
    
    @Published var isProcessing = false
    @Published var showError = false
    @Published var errorMessage = ""
    @Published var sentTips: [Tip] = []
    @Published var receivedTips: [Tip] = []
    @Published var balance: Double = 0.0
    @Published var selectedAmount: Double?
    @Published var showSuccessAlert = false
    @Published var paymentSheet: PaymentSheet?
    @Published var isPaymentSheetPresented = false
    @Published var isRapidTipping = false
    
    private let db = Firestore.firestore()
    private var hasInitialized = false
    private lazy var stripeService = StripeService.shared
    
    let tipAmounts = [1.00, 5.00, 10.00, 20.00]
    
    private var rapidTipTask: Task<Void, Never>?
    private var lastTipTime: Date?
    private let minimumTipInterval: TimeInterval = 0.1 // 100ms between tips
    private var onTipCallback: ((Double) -> Void)?
    
    var isPurchasing: Bool {
        isProcessing
    }
    
    private init() {
        Task {
            await initialize()
        }
    }
    
    private func initialize() async {
        guard !hasInitialized else { return }
        hasInitialized = true
        
        // Only load balance once during initialization
        await loadBalance()
        // Load tip history without triggering balance load
        await loadTipHistoryWithoutBalance()
    }
    
    // Helper method to get user-specific balance key
    private func getUserBalanceKey() -> String? {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return nil }
        return "userBalance_\(userId)"
    }
    
    // Helper method to get development mode balance
    private func getDevelopmentBalance() -> Double {
        guard let balanceKey = getUserBalanceKey() else { return 0.0 }
        return UserDefaults.standard.double(forKey: balanceKey)
    }
    
    // Helper method to set development mode balance
    private func setDevelopmentBalance(_ amount: Double) {
        guard let balanceKey = getUserBalanceKey() else { return }
        UserDefaults.standard.set(amount, forKey: balanceKey)
    }
    
    // MARK: - Public Methods
    
    private func logBalanceChange(oldBalance: Double, newBalance: Double, reason: String, details: [String: Any] = [:]) {
        let change = newBalance - oldBalance
        // Only log if there's an actual change or if it's a tip operation
        if abs(change) > 0.001 || reason.contains("Tip") {
            let timestamp = Date()
            let mode = "Development"
            
            var logDetails: [String: Any] = [
                "timestamp": timestamp,
                "mode": mode,
                "oldBalance": String(format: "%.2f", oldBalance),
                "newBalance": String(format: "%.2f", newBalance),
                "change": String(format: "%+.2f", change),
                "reason": reason
            ]
            logDetails.merge(details) { current, _ in current }
            
            print("💰 Balance Change Log:")
            print("  Time: \(timestamp)")
            print("  Mode: \(mode)")
            print("  Change: $\(String(format: "%+.2f", change)) (\(reason))")
            print("  Old Balance: $\(String(format: "%.2f", oldBalance))")
            print("  New Balance: $\(String(format: "%.2f", newBalance))")
            if !details.isEmpty {
                print("  Details:", details)
            }
            print("  ----------------------")
        }
    }
    
    @MainActor
    func addFunds(_ amount: Double) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let serverURL = try await Configuration.getServerURL()
            let backendUrl = serverURL.appendingPathComponent("create-payment-intent")
            
            var request = URLRequest(url: backendUrl)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            let body: [String: Any] = [
                "amount": Int(amount * 100),
                "currency": "usd"
            ]
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
            
            let (data, _) = try await URLSession.shared.data(for: request)
            
            // Print the raw response for debugging
            if let responseString = String(data: data, encoding: .utf8) {
                print("Server response: \(responseString)")
            }
            
            guard let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
                  let clientSecret = json["clientSecret"] as? String,
                  let publishableKey = json["publishableKey"] as? String else {
                throw NSError(domain: "PaymentError", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
            }
            
            // Update Stripe publishable key from server
            StripeAPI.defaultPublishableKey = publishableKey
            
            // Configure payment sheet with minimal test settings
            var configuration = PaymentSheet.Configuration()
            configuration.merchantDisplayName = "ClikTok"
            configuration.returnURL = "cliktok://stripe-redirect"
            
            paymentSheet = PaymentSheet(
                paymentIntentClientSecret: clientSecret,
                configuration: configuration
            )
            
            isPaymentSheetPresented = true
            
        } catch {
            print("Error: \(error)")
            throw error
        }
    }
    
    func handlePaymentCompletion(_ result: PaymentSheetResult) async {
        switch result {
        case .completed:
            print("Payment completed!")
            // Update development balance with the selected amount
            if let amount = selectedAmount {
                let oldBalance = balance
                let newBalance = oldBalance + amount
                balance = newBalance
                setDevelopmentBalance(newBalance)
                logBalanceChange(oldBalance: oldBalance, 
                               newBalance: newBalance, 
                               reason: "Added Funds",
                               details: ["amount": amount])
            }
            showSuccessAlert = true
            
        case .canceled:
            print("Payment canceled.")
            errorMessage = "Payment was canceled"
            showError = true
            
        case .failed(let error):
            print("Payment failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
            showError = true
        }
    }
    
    @MainActor
    func prepareTip(amount: Double) async throws {
        // Always check balance first
        guard amount <= balance else {
            throw PaymentError.insufficientFunds
        }
        
        self.selectedAmount = amount
        print("Preparing tip of $\(String(format: "%.2f", amount))")
        
        do {
            // Process tip directly from balance
            try await processTip(amount: amount, receiverID: "", videoID: "")
            showSuccessAlert = true
        } catch {
            print("Failed to process tip: \(error)")
            throw error
        }
    }
    
    func sendTip(to receiverID: String, for videoID: String) async throws {
        // Check if user has enough balance
        if balance < 0.01 {
            throw NSError(domain: "TipError", code: 402, userInfo: [NSLocalizedDescriptionKey: "Insufficient balance"])
        }
        
        try await processTip(amount: 0.01, receiverID: receiverID, videoID: videoID)
    }
    
    func loadTipHistory() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            // Load sent tips
            let sentSnapshot = try await db.collection("tips")
                .whereField("senderID", isEqualTo: userId)
                .getDocuments()
            
            self.sentTips = try sentSnapshot.documents.compactMap { document in
                try document.data(as: Tip.self)
            }
            
            // Load received tips
            let receivedSnapshot = try await db.collection("tips")
                .whereField("receiverID", isEqualTo: userId)
                .getDocuments()
            
            self.receivedTips = try receivedSnapshot.documents.compactMap { document in
                try document.data(as: Tip.self)
            }
            
        } catch {
            print("Error loading tip history: \(error)")
        }
    }
    
    @MainActor
    func sendMinimumTip(receiverID: String, videoID: String) async throws {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            try await processTip(amount: 0.01, receiverID: receiverID, videoID: videoID)
            // Refresh tip history after successful tip
            await loadTipHistory()
        } catch {
            throw error
        }
    }
    
    @MainActor
    func loadBalance() async {
        let oldBalance = balance
        
        let newBalance = getDevelopmentBalance()
        // Only update and log if there's an actual change
        if abs(newBalance - oldBalance) > 0.001 {
            balance = newBalance
            logBalanceChange(oldBalance: oldBalance, 
                           newBalance: balance, 
                           reason: "Development Balance Load")
        }
    }
    
    @MainActor
    func updateBalance(amount: Double) async throws {
        // Balance is handled by PaymentManager in dev mode
        return 
    }
    
    private func processTip(amount: Double, receiverID: String, videoID: String) async throws {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "TipError", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        // Check balance
        guard amount <= balance else {
            throw PaymentError.insufficientFunds
        }
        
        let oldBalance = balance
        
        // Create tip record with minimal data for rapid tipping
        let tip = Tip(
            amount: amount,
            timestamp: Date(),
            videoID: videoID,  // Keep the videoID as is, with archive_ prefix if present
            senderID: userId,
            receiverID: receiverID,
            transactionID: UUID().uuidString
        )
        
        do {
            // Store tip in Firestore using Codable
            let tipRef = db.collection("tips").document()
            try tipRef.setData(from: tip)
            
            // Update balance in memory and UserDefaults
            balance -= amount
            setDevelopmentBalance(balance)
            
            // Only log balance changes for non-rapid tips or at intervals
            if !isRapidTipping || lastTipTime == nil || 
               Date().timeIntervalSince(lastTipTime!) > 1.0 {
                logBalanceChange(
                    oldBalance: oldBalance,
                    newBalance: balance,
                    reason: isRapidTipping ? "Rapid Tip" : "Tip Sent",
                    details: [
                        "tipId": tipRef.documentID,
                        "videoId": videoID,
                        "receiverId": receiverID
                    ]
                )
            }
            
            // Only refresh tip history periodically during rapid tipping
            if !isRapidTipping {
                await loadTipHistory()
            }
        } catch {
            // Revert balance on failure
            balance = oldBalance
            setDevelopmentBalance(oldBalance)
            throw error
        }
    }
    
    private func loadTipHistoryWithoutBalance() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            // Load sent tips
            let sentSnapshot = try await db.collection("tips")
                .whereField("senderID", isEqualTo: userId)
                .getDocuments()
            
            self.sentTips = try sentSnapshot.documents.compactMap { document in
                try document.data(as: Tip.self)
            }
            
            // Load received tips
            let receivedSnapshot = try await db.collection("tips")
                .whereField("receiverID", isEqualTo: userId)
                .getDocuments()
            
            self.receivedTips = try receivedSnapshot.documents.compactMap { document in
                try document.data(as: Tip.self)
            }
        } catch {
            print("Error loading tip history: \(error)")
        }
    }
    
    private func createPaymentIntent(amount: Double) async throws -> String {
        let serverURL = try await Configuration.getServerURL()
        let url = serverURL.appendingPathComponent("create-payment-intent")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Convert amount to cents
        let amountInCents = Int(amount * 100)
        let body = ["amount": amountInCents]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        
        let (data, _) = try await URLSession.shared.data(for: request)
        let response = try JSONDecoder().decode(StripePaymentIntentResponse.self, from: data)
        return response.clientSecret
    }
    
    private func fetchStripeConfig() async throws -> String {
        let serverURL = try await Configuration.getServerURL()
        let url = serverURL.appendingPathComponent("config")
        
        let (data, _) = try await URLSession.shared.data(from: url)
        let config = try JSONDecoder().decode(StripeConfig.self, from: data)
        return config.publishableKey
    }
    
    func startRapidTipping(receiverID: String, videoID: String, onTip: @escaping (Double) -> Void) {
        guard !isRapidTipping else { return }
        isRapidTipping = true
        lastTipTime = nil
        onTipCallback = onTip
        
        rapidTipTask = Task { @MainActor in
            while !Task.isCancelled && isRapidTipping {
                // Check if enough time has passed since last tip
                let now = Date()
                if let lastTip = lastTipTime, 
                   now.timeIntervalSince(lastTip) < minimumTipInterval {
                    try? await Task.sleep(nanoseconds: UInt64(0.05 * 1_000_000_000))
                    continue
                }
                
                // Check balance before attempting tip
                guard balance >= 0.01 else {
                    isRapidTipping = false
                    break
                }
                
                do {
                    try await processTip(amount: 0.01, receiverID: receiverID, videoID: videoID)
                    lastTipTime = Date()
                    onTipCallback?(0.01)
                } catch {
                    print("Rapid tipping error: \(error)")
                    isRapidTipping = false
                    break
                }
                
                // Small delay to prevent overwhelming the system
                try? await Task.sleep(nanoseconds: UInt64(0.05 * 1_000_000_000))
            }
            isRapidTipping = false
            onTipCallback = nil
        }
    }
    
    func stopRapidTipping() {
        isRapidTipping = false
        rapidTipTask?.cancel()
        rapidTipTask = nil
        onTipCallback = nil
    }
}