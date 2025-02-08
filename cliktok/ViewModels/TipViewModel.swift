import SwiftUI
import FirebaseFirestore
import StripePaymentSheet
import Foundation

@MainActor
class TipViewModel: ObservableObject {
    static let shared = TipViewModel()
    
    @Published var isProcessing = false
    @Published var error: Error?
    @Published var sentTips: [Tip] = []
    @Published var receivedTips: [Tip] = []
    @Published var balance: Double = 0.0
    @Published var selectedAmount: Double?
    @Published var showSuccessAlert = false
    
    private let db = Firestore.firestore()
    private let paymentManager = PaymentManager.shared
    private var hasInitialized = false
    
    let tipAmounts = [1.00, 5.00, 10.00, 20.00]
    
    var isPurchasing: Bool {
        paymentManager.isLoading
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
            let mode = if paymentManager.isDevelopmentMode {
                "Development"
            } else if paymentManager.isTestMode {
                "Test"
            } else {
                "Production"
            }
            
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
        
        if paymentManager.isDevelopmentMode {
            print("Adding funds in development mode: \(amount)")
            let decimalAmount = NSDecimalNumber(value: amount).decimalValue
            paymentManager.addTestMoney(amount: decimalAmount)
            balance = getDevelopmentBalance()
            logBalanceChange(oldBalance: oldBalance, 
                           newBalance: balance, 
                           reason: "Added Test Funds",
                           details: ["requestedAmount": amount])
        } else {
            do {
                // Use PaymentSheet for adding real funds (both test and production modes)
                let amountInCents = Int(amount * 100)
                let paymentSheet = try await paymentManager.createPaymentIntent(amount: amountInCents)
                
                // Present the payment sheet
                if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                   let rootViewController = windowScene.windows.first?.rootViewController {
                    
                    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                        paymentSheet.present(from: rootViewController) { [weak self] (result: PaymentSheetResult) in
                            guard let self = self else {
                                continuation.resume()
                                return
                            }
                            
                            Task { @MainActor in
                                switch result {
                                case .completed:
                                    print("Payment successful")
                                    // Update balance after successful payment
                                    let newBalance = self.balance + amount
                                    try? await self.updateBalance(amount: newBalance)
                                    self.logBalanceChange(oldBalance: oldBalance,
                                                        newBalance: newBalance,
                                                        reason: "Added \(self.paymentManager.isTestMode ? "Test" : "Production") Funds",
                                                        details: ["requestedAmount": amount,
                                                                "mode": self.paymentManager.isTestMode ? "test" : "production"])
                                    self.showSuccessAlert = true
                                    
                                case .canceled:
                                    print("Payment canceled")
                                    
                                case .failed(let error):
                                    print("Payment failed: \(error.localizedDescription)")
                                    self.error = error
                                }
                            }
                            
                            continuation.resume()
                        }
                    }
                }
            } catch {
                print("Failed to add funds: \(error)")
                throw error
            }
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
        
        if paymentManager.isDevelopmentMode {
            let newBalance = getDevelopmentBalance()
            // Only update and log if there's an actual change
            if abs(newBalance - oldBalance) > 0.001 {
                balance = newBalance
                logBalanceChange(oldBalance: oldBalance, 
                               newBalance: balance, 
                               reason: "Development Balance Load")
            }
        } else {
            guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
            
            do {
                let userRef = db.collection("users").document(userId)
                let doc = try await userRef.getDocument()
                
                if !doc.exists {
                    try await userRef.setData([
                        "balance": 0.0,
                        "createdAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                    balance = 0.0
                    logBalanceChange(oldBalance: oldBalance, 
                                   newBalance: 0.0, 
                                   reason: "New User Account Created")
                } else if let userBalance = doc.data()?["balance"] as? Double {
                    // Only update and log if there's an actual change
                    if abs(userBalance - oldBalance) > 0.001 {
                        balance = userBalance
                        logBalanceChange(oldBalance: oldBalance, 
                                       newBalance: userBalance, 
                                       reason: "\(paymentManager.isTestMode ? "Test" : "Production") Balance Load")
                    }
                }
            } catch {
                print("Error loading balance: \(error)")
            }
        }
    }
    
    @MainActor
    func updateBalance(amount: Double) async throws {
        if paymentManager.isDevelopmentMode {
            return // Balance is handled by PaymentManager in dev mode
        }
        
        guard let userId = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "TipViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        let userRef = db.collection("users").document(userId)
        
        do {
            // First check if document exists
            let doc = try await userRef.getDocument()
            if !doc.exists {
                // Create user document if it doesn't exist
                try await userRef.setData([
                    "balance": amount,
                    "createdAt": FieldValue.serverTimestamp(),
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            } else {
                // Update existing document
                try await userRef.updateData([
                    "balance": amount,
                    "updatedAt": FieldValue.serverTimestamp()
                ])
            }
            
            self.balance = amount
        } catch {
            print("Error updating balance: \(error)")
            throw error
        }
    }
    
    private func processTip(amount: Double, receiverID: String, videoID: String) async throws {
        let oldBalance = balance
        
        guard let senderID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "TipViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Check if this is a self-tip
        let isSelfTip = senderID == receiverID
        
        if paymentManager.isDevelopmentMode {
            let currentBalance = getDevelopmentBalance()
            guard currentBalance >= amount else {
                throw PaymentError.insufficientFunds
            }
            
            // Update sender's balance
            setDevelopmentBalance(currentBalance - amount)
            
            // Update receiver's balance if it's not a self-tip
            if !isSelfTip {
                let receiverBalanceKey = "userBalance_\(receiverID)"
                let receiverCurrentBalance = UserDefaults.standard.double(forKey: receiverBalanceKey)
                UserDefaults.standard.set(receiverCurrentBalance + amount, forKey: receiverBalanceKey)
            }
            
            // Update local balance state
            balance = getDevelopmentBalance()
            
            // Create tip record
            let tipRef = db.collection("tips").document()
            let tipData: [String: Any] = [
                "amount": amount,
                "timestamp": FieldValue.serverTimestamp(),
                "videoID": videoID,
                "senderID": senderID,
                "receiverID": receiverID,
                "transactionID": UUID().uuidString,
                "mode": "development"
            ]
            
            try await tipRef.setData(tipData)
            
            // Log the sent tip
            logBalanceChange(oldBalance: oldBalance, 
                           newBalance: balance, 
                           reason: "Sent Tip (Development)",
                           details: ["receiverID": receiverID,
                                   "videoID": videoID,
                                   "tipAmount": amount,
                                   "isSelfTip": isSelfTip])
            
            // Refresh tip history without loading balance
            await loadTipHistoryWithoutBalance()
            return
        }
        
        // Production/Test mode handling
        await loadBalance()
        
        if balance < amount {
            throw PaymentError.insufficientFunds
        }
        
        // Create transaction record
        let tipRef = self.db.collection("tips").document()
        let transactionID = UUID().uuidString
        
        let tipData: [String: Any] = [
            "amount": amount,
            "timestamp": FieldValue.serverTimestamp(),
            "videoID": videoID,
            "senderID": senderID,
            "receiverID": receiverID,
            "transactionID": transactionID,
            "mode": paymentManager.isTestMode ? "test" : "production"
        ]
        
        // Update balances and create tip record
        do {
            try await self.db.runTransaction({ [weak self] (transaction, errorPointer) -> Any? in
                guard let self = self else { return nil }
                do {
                    // Get current balances
                    let senderDoc = try transaction.getDocument(self.db.collection("users").document(senderID))
                    let receiverDoc = try transaction.getDocument(self.db.collection("users").document(receiverID))
                    
                    let senderBalance = (senderDoc.data()?["balance"] as? Double) ?? 0
                    let receiverBalance = (receiverDoc.data()?["balance"] as? Double) ?? 0
                    
                    // Verify sender has sufficient balance
                    if senderBalance < amount {
                        let error = NSError(domain: "TipError", code: 402, userInfo: [NSLocalizedDescriptionKey: "Insufficient funds"])
                        errorPointer?.pointee = error
                        return nil
                    }
                    
                    // Always update balances, even for self-tips
                    transaction.updateData(["balance": senderBalance - amount], forDocument: self.db.collection("users").document(senderID))
                    transaction.updateData(["balance": receiverBalance + amount], forDocument: self.db.collection("users").document(receiverID))
                    
                    // Create tip record
                    transaction.setData(tipData, forDocument: tipRef)
                    
                    return nil
                } catch {
                    errorPointer?.pointee = error as NSError
                    return nil
                }
            })
            
            // Update local balance
            if isSelfTip {
                // For self-tips, balance doesn't change
                await loadBalance()
            } else {
                balance -= amount
            }
            
            // Refresh tip history without loading balance
            await loadTipHistoryWithoutBalance()
            
            // Log the tip
            logBalanceChange(oldBalance: oldBalance, 
                           newBalance: balance, 
                           reason: "Sent Tip (\(paymentManager.isTestMode ? "Test" : "Production"))",
                           details: ["receiverID": receiverID,
                                   "videoID": videoID,
                                   "tipAmount": amount,
                                   "isSelfTip": isSelfTip])
        } catch {
            print("Error processing tip: \(error)")
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