import SwiftUI
import FirebaseFirestore
import Foundation
import StripePaymentSheet

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
    
    private let db = Firestore.firestore()
    private var hasInitialized = false
    private let stripeService = StripeService.shared
    
    let tipAmounts = [1.00, 5.00, 10.00, 20.00]
    
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
            let backendUrl = URL(string: "http://192.168.1.69:3000/create-payment-intent")!
            
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
            await loadBalance()
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
            
            self.sentTips = sentSnapshot.documents.compactMap { document in
                guard let amount = document.data()["amount"] as? Double,
                      let timestamp = (document.data()["timestamp"] as? Timestamp)?.dateValue(),
                      let videoID = document.data()["videoID"] as? String,
                      let senderID = document.data()["senderID"] as? String,
                      let receiverID = document.data()["receiverID"] as? String,
                      let transactionID = document.data()["transactionID"] as? String else {
                    return nil
                }
                
                return Tip(id: document.documentID,
                          amount: amount,
                          timestamp: timestamp,
                          videoID: videoID,
                          senderID: senderID,
                          receiverID: receiverID,
                          transactionID: transactionID)
            }
            
            // Load received tips
            let receivedSnapshot = try await db.collection("tips")
                .whereField("receiverID", isEqualTo: userId)
                .getDocuments()
            
            self.receivedTips = receivedSnapshot.documents.compactMap { document in
                guard let amount = document.data()["amount"] as? Double,
                      let timestamp = (document.data()["timestamp"] as? Timestamp)?.dateValue(),
                      let videoID = document.data()["videoID"] as? String,
                      let senderID = document.data()["senderID"] as? String,
                      let receiverID = document.data()["receiverID"] as? String,
                      let transactionID = document.data()["transactionID"] as? String else {
                    return nil
                }
                
                return Tip(id: document.documentID,
                          amount: amount,
                          timestamp: timestamp,
                          videoID: videoID,
                          senderID: senderID,
                          receiverID: receiverID,
                          transactionID: transactionID)
            }
            
            // Remove unnecessary balance load in development mode
            // The balance is already handled in processTip
            
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
        
        // Create transaction record
        let transaction = Transaction(
            userID: userId,
            type: .tip,
            amount: amount,
            status: .completed,
            description: "Tip for video \(videoID)"
        )
        
        // Create tip record
        let tip = Tip(
            id: UUID().uuidString,
            amount: amount,
            timestamp: Date(),
            videoID: videoID,
            senderID: userId,
            receiverID: receiverID,
            transactionID: transaction.id
        )
        
        do {
            // Store tip in Firestore
            try await db.collection("tips").document(tip.id).setData([
                "amount": tip.amount,
                "timestamp": tip.timestamp,
                "videoID": tip.videoID,
                "senderID": tip.senderID,
                "receiverID": tip.receiverID,
                "transactionID": tip.transactionID
            ])
            
            // Update balance
            balance -= amount
            
            // Log balance change
            logBalanceChange(
                oldBalance: oldBalance,
                newBalance: balance,
                reason: "Tip Sent",
                details: [
                    "tipId": tip.id,
                    "videoId": videoID,
                    "receiverId": receiverID
                ]
            )
            
            // Refresh tip history
            await loadTipHistory()
        } catch {
            // Revert balance on failure
            balance = oldBalance
            throw error
        }
    }
    
    // New method that loads tip history without affecting balance
    private func loadTipHistoryWithoutBalance() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            // Load sent tips
            let sentSnapshot = try await db.collection("tips")
                .whereField("senderID", isEqualTo: userId)
                .getDocuments()
            
            self.sentTips = sentSnapshot.documents.compactMap { document in
                guard let amount = document.data()["amount"] as? Double,
                      let timestamp = (document.data()["timestamp"] as? Timestamp)?.dateValue(),
                      let videoID = document.data()["videoID"] as? String,
                      let senderID = document.data()["senderID"] as? String,
                      let receiverID = document.data()["receiverID"] as? String,
                      let transactionID = document.data()["transactionID"] as? String else {
                    return nil
                }
                
                return Tip(id: document.documentID,
                          amount: amount,
                          timestamp: timestamp,
                          videoID: videoID,
                          senderID: senderID,
                          receiverID: receiverID,
                          transactionID: transactionID)
            }
            
            // Load received tips
            let receivedSnapshot = try await db.collection("tips")
                .whereField("receiverID", isEqualTo: userId)
                .getDocuments()
            
            self.receivedTips = receivedSnapshot.documents.compactMap { document in
                guard let amount = document.data()["amount"] as? Double,
                      let timestamp = (document.data()["timestamp"] as? Timestamp)?.dateValue(),
                      let videoID = document.data()["videoID"] as? String,
                      let senderID = document.data()["senderID"] as? String,
                      let receiverID = document.data()["receiverID"] as? String,
                      let transactionID = document.data()["transactionID"] as? String else {
                    return nil
                }
                
                return Tip(id: document.documentID,
                          amount: amount,
                          timestamp: timestamp,
                          videoID: videoID,
                          senderID: senderID,
                          receiverID: receiverID,
                          transactionID: transactionID)
            }
        } catch {
            print("Error loading tip history: \(error)")
        }
    }
}