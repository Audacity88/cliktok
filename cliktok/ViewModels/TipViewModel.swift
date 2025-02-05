import SwiftUI
import FirebaseFirestore
import StripePayments
import Foundation

@MainActor
class TipViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var error: Error?
    @Published var tipHistory: [Tip] = []
    @Published var balance: Double = 0.0
    @Published var selectedAmount: Double?
    @Published var showSuccessAlert = false
    
    private let db = Firestore.firestore()
    private let paymentManager = PaymentManager.shared
    
    let tipAmounts = [1.00, 5.00, 10.00, 20.00]
    
    var isPurchasing: Bool {
        paymentManager.isLoading
    }
    
    // MARK: - Public Methods
    
    @MainActor
    func addFunds(_ amount: Double) async {
        if paymentManager.isDevelopmentMode {
            let decimalAmount = NSDecimalNumber(value: amount).decimalValue
            paymentManager.addTestMoney(amount: decimalAmount)
            let currentBalance = paymentManager.getCurrentBalance()
            balance = NSDecimalNumber(decimal: currentBalance).doubleValue
        } else {
            do {
                let newBalance = balance + amount
                try await updateBalance(amount: newBalance)
                print("Successfully added $\(amount). New balance: $\(newBalance)")
            } catch {
                print("Failed to add funds: \(error)")
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
    
    @MainActor
    func loadBalance() async {
        if paymentManager.isDevelopmentMode {
            balance = NSDecimalNumber(decimal: paymentManager.getCurrentBalance()).doubleValue
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
    
    func loadTipHistory() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            let querySnapshot = try await db.collection("tips")
                .whereField("senderID", isEqualTo: userId)
                .order(by: "timestamp", descending: true)
                .limit(to: 10)
                .getDocuments()
            
            tipHistory = querySnapshot.documents.compactMap { document -> Tip? in
                let data = document.data()
                guard let id = document.documentID as String?,
                      let amount = data["amount"] as? Double,
                      let timestamp = (data["timestamp"] as? Timestamp)?.dateValue(),
                      let videoID = data["videoID"] as? String,
                      let senderID = data["senderID"] as? String,
                      let receiverID = data["receiverID"] as? String,
                      let transactionID = data["transactionID"] as? String
                else { return nil }
                
                return Tip(
                    id: id,
                    amount: amount,
                    timestamp: timestamp,
                    videoID: videoID,
                    senderID: senderID,
                    receiverID: receiverID,
                    transactionID: transactionID
                )
            }
        } catch {
            print("Error loading tip history: \(error)")
        }
    }
    
    // MARK: - Private Methods
    
    private func processTip(amount: Double, receiverID: String, videoID: String) async throws {
        guard let senderID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "TipViewModel", code: -1, userInfo: [NSLocalizedDescriptionKey: "User not logged in"])
        }
        
        let tipId = UUID().uuidString
        let now = Date()
        let timestamp = Timestamp(date: now)
        
        do {
            // Create or get sender document
            let senderRef = db.collection("users").document(senderID)
            let senderDoc = try await senderRef.getDocument()
            
            if !senderDoc.exists {
                try await senderRef.setData([
                    "balance": 0.0,
                    "createdAt": timestamp,
                    "updatedAt": timestamp
                ])
            }
            
            // Create or get receiver document
            let receiverRef = db.collection("users").document(receiverID)
            let receiverDoc = try await receiverRef.getDocument()
            
            if !receiverDoc.exists {
                try await receiverRef.setData([
                    "balance": 0.0,
                    "createdAt": timestamp,
                    "updatedAt": timestamp
                ])
            }
            
            // Get current balances
            let senderBalance = (senderDoc.data()?["balance"] as? Double) ?? 0.0
            let receiverBalance = (receiverDoc.data()?["balance"] as? Double) ?? 0.0
            
            // Update balances
            try await senderRef.updateData([
                "balance": senderBalance - amount,
                "updatedAt": timestamp
            ])
            
            try await receiverRef.updateData([
                "balance": receiverBalance + amount,
                "updatedAt": timestamp
            ])
            
            // Record the tip
            try await db.collection("tips").document(tipId).setData([
                "senderID": senderID,
                "receiverID": receiverID,
                "videoID": videoID,
                "amount": amount,
                "timestamp": timestamp,
                "transactionID": tipId
            ])
            
            // Add tip to local history
            let tip = Tip(
                id: tipId,
                amount: amount,
                timestamp: now,
                videoID: videoID,
                senderID: senderID,
                receiverID: receiverID,
                transactionID: tipId
            )
            tipHistory.append(tip)
            
        } catch {
            print("Error processing tip: \(error)")
            throw error
        }
    }
    
    @MainActor
    func sendMinimumTip(receiverID: String, videoID: String) async throws {
        let tipAmount = 0.01 // 1 cent tip
        
        if paymentManager.isDevelopmentMode {
            // Check if we have enough balance
            let currentBalance = paymentManager.getCurrentBalance()
            if currentBalance < Decimal(tipAmount) {
                throw PaymentError.insufficientFunds
            }
            
            // Deduct from balance
            if !paymentManager.useBalance(amount: Decimal(tipAmount)) {
                throw PaymentError.insufficientFunds
            }
            
            // Record the tip
            try await processTip(amount: tipAmount, receiverID: receiverID, videoID: videoID)
            
            // Update local balance
            balance = NSDecimalNumber(decimal: paymentManager.getCurrentBalance()).doubleValue
        } else {
            // Handle production mode
            try await prepareTip(amount: tipAmount)
            try await processTip(amount: tipAmount, receiverID: receiverID, videoID: videoID)
        }
        
        // Refresh tip history
        await loadTipHistory()
    }
}