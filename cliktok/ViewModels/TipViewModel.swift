import SwiftUI
import FirebaseFirestore
import Foundation

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
    
    private let db = Firestore.firestore()
    private var hasInitialized = false
    
    let tipAmounts = [1.00, 5.00, 10.00, 20.00]
    
    var isPurchasing: Bool {
        false
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
        let oldBalance = balance
        
        print("Adding funds in development mode: \(amount)")
        let decimalAmount = NSDecimalNumber(value: amount).decimalValue
        // paymentManager.addTestMoney(amount: decimalAmount)
        balance = getDevelopmentBalance()
        logBalanceChange(oldBalance: oldBalance, 
                       newBalance: balance, 
                       reason: "Added Test Funds",
                       details: ["requestedAmount": amount])
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
    
    private func processTip(amount: Double, receiverID: String, videoID: String) async -> Bool {
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // TODO: Implement tipping without Stripe
            return true
        } catch {
            errorMessage = error.localizedDescription
            showError = true
            return false
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