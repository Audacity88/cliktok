import SwiftUI
import FirebaseFirestore
import StripePayments
import Foundation

@MainActor
class TipViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var error: Error?
    @Published var sentTips: [Tip] = []
    @Published var receivedTips: [Tip] = []
    @Published var balance: Double = 0.0
    @Published var selectedAmount: Double?
    @Published var showSuccessAlert = false
    
    private let db = Firestore.firestore()
    private let paymentManager = PaymentManager.shared
    
    let tipAmounts = [1.00, 5.00, 10.00, 20.00]
    
    var isPurchasing: Bool {
        paymentManager.isLoading
    }
    
    init() {
        Task {
            await loadBalance()
            await loadTipHistory()
        }
    }
    
    // MARK: - Public Methods
    
    @MainActor
    func addFunds(_ amount: Double) async throws {
        if paymentManager.isDevelopmentMode {
            print("Adding funds in development mode: \(amount)")
            let decimalAmount = NSDecimalNumber(value: amount).decimalValue
            paymentManager.addTestMoney(amount: decimalAmount)
            balance = NSDecimalNumber(decimal: paymentManager.getCurrentBalance()).doubleValue
            print("New balance after adding funds: \(balance)")
        } else {
            do {
                let newBalance = balance + amount
                try await updateBalance(amount: newBalance)
                print("Successfully added $\(amount). New balance: $\(newBalance)")
            } catch {
                print("Failed to add funds: \(error)")
                throw error
            }
        }
    }
    
    @MainActor
    func prepareTip(amount: Double) async throws {
        // Ensure user document exists before proceeding
        if !paymentManager.isDevelopmentMode {
            await loadBalance() // This will create the user document if it doesn't exist
        }
        
        self.selectedAmount = amount
        let amountInCents = Int(amount * 100)
        print("Preparing tip of $\(amount) (\(amountInCents) cents)")
        let clientSecret = try await paymentManager.createPaymentIntent(amount: amountInCents)
        print("Payment successful with client secret: \(clientSecret)")
        
        // If we get here, payment was successful
        if let amount = selectedAmount {
            print("Successfully processed tip of $\(String(format: "%.2f", amount))")
            showSuccessAlert = true
            // Refresh balance after successful tip
            await loadBalance()
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
                .order(by: "timestamp", descending: true)
                .limit(to: 20)
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
                .order(by: "timestamp", descending: true)
                .limit(to: 20)
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
            
            // Add received tips to balance in development mode
            if paymentManager.isDevelopmentMode {
                let totalReceived = receivedTips.reduce(0.0) { $0 + $1.amount }
                if totalReceived > 0 {
                    paymentManager.addTestMoney(amount: NSDecimalNumber(value: totalReceived).decimalValue)
                    balance = NSDecimalNumber(decimal: paymentManager.getCurrentBalance()).doubleValue
                }
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
        if paymentManager.isDevelopmentMode {
            let currentBalance = paymentManager.getCurrentBalance()
            balance = NSDecimalNumber(decimal: currentBalance).doubleValue
            print("Loaded development mode balance: \(balance)")
        } else {
            guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
            
            do {
                let userRef = db.collection("users").document(userId)
                let doc = try await userRef.getDocument()
                
                if !doc.exists {
                    // Create user document if it doesn't exist
                    try await userRef.setData([
                        "balance": 0.0,
                        "createdAt": FieldValue.serverTimestamp(),
                        "updatedAt": FieldValue.serverTimestamp()
                    ])
                    balance = 0.0
                } else if let userBalance = doc.data()?["balance"] as? Double {
                    balance = userBalance
                }
                print("Loaded production mode balance: \(balance)")
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
        guard let senderID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "TipViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        // Check balance
        if paymentManager.isDevelopmentMode {
            let decimalAmount = NSDecimalNumber(value: amount).decimalValue
            if !paymentManager.useBalance(amount: decimalAmount) {
                throw PaymentError.insufficientFunds
            }
            // Update local balance after successful tip
            balance = NSDecimalNumber(decimal: paymentManager.getCurrentBalance()).doubleValue
            
            // Create tip record
            let tipRef = db.collection("tips").document()
            let tipData: [String: Any] = [
                "amount": amount,
                "timestamp": FieldValue.serverTimestamp(),
                "videoID": videoID,
                "senderID": senderID,
                "receiverID": receiverID,
                "transactionID": UUID().uuidString
            ]
            
            try await tipRef.setData(tipData)
            
            // Refresh tip history
            await loadTipHistory()
            return
        }
        
        // Production mode handling
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
            "transactionID": transactionID
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
                    
                    // Update balances
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
            balance -= amount
            
            // Refresh tip history
            await loadTipHistory()
        } catch {
            print("Error processing tip: \(error)")
            throw error
        }
    }
}