import Foundation
import FirebaseFirestore
import StoreKit

@MainActor
class TipViewModel: ObservableObject {
    @Published var isProcessing = false
    @Published var error: Error?
    @Published var tipHistory: [Tip] = []
    @Published var balance: Double = 0.0
    
    private let db = Firestore.firestore()
    private let defaultTipAmount = 0.01 // $0.01 per tip
    
    func sendTip(to receiverID: String, for videoID: String) async throws {
        guard let senderID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "Tipping", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            // Check user balance
            if balance < defaultTipAmount {
                throw NSError(domain: "Tipping", code: 402, userInfo: [NSLocalizedDescriptionKey: "Insufficient balance"])
            }
            
            // Create transaction ID
            let transactionID = UUID().uuidString
            
            // Create tip document
            let tip = Tip(
                videoID: videoID,
                senderID: senderID,
                receiverID: receiverID,
                amount: defaultTipAmount,
                transactionID: transactionID
            )
            
            // Create transaction for sender (debit)
            let senderTransaction = Transaction(
                userID: senderID,
                type: .tip,
                amount: -defaultTipAmount,
                status: .completed,
                description: "Tip sent for video"
            )
            
            // Create transaction for receiver (credit)
            let receiverTransaction = Transaction(
                userID: receiverID,
                type: .tip,
                amount: defaultTipAmount,
                status: .completed,
                description: "Tip received for video"
            )
            
            // Batch write to Firestore
            let batch = db.batch()
            
            // Add tip document
            let tipRef = db.collection("tips").document(tip.id)
            try batch.setData(from: tip, forDocument: tipRef)
            
            // Add transactions
            let senderTransactionRef = db.collection("transactions").document(senderTransaction.id)
            try batch.setData(from: senderTransaction, forDocument: senderTransactionRef)
            
            let receiverTransactionRef = db.collection("transactions").document(receiverTransaction.id)
            try batch.setData(from: receiverTransaction, forDocument: receiverTransactionRef)
            
            // Update balances
            let senderRef = db.collection("users").document(senderID)
            let receiverRef = db.collection("users").document(receiverID)
            
            batch.updateData(["balance": FieldValue.increment(-defaultTipAmount)], forDocument: senderRef)
            batch.updateData(["balance": FieldValue.increment(defaultTipAmount)], forDocument: receiverRef)
            
            // Commit the batch
            try await batch.commit()
            
            // Update local balance
            balance -= defaultTipAmount
            
            // Add to local tip history
            tipHistory.append(tip)
            
        } catch {
            self.error = error
            throw error
        }
    }
    
    func loadBalance() async {
        guard let userID = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            let document = try await db.collection("users").document(userID).getDocument()
            if let balance = document.data()?["balance"] as? Double {
                self.balance = balance
            }
        } catch {
            self.error = error
        }
    }
    
    func loadTipHistory() async {
        guard let userID = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            let query = db.collection("tips")
                .whereField("senderID", isEqualTo: userID)
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
            
            let snapshot = try await query.getDocuments()
            tipHistory = try snapshot.documents.compactMap { try $0.data(as: Tip.self) }
        } catch {
            self.error = error
        }
    }
    
    func addFunds(_ amount: Double) async throws {
        guard let userID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "Payment", code: 401, userInfo: [NSLocalizedDescriptionKey: "User not authenticated"])
        }
        
        isProcessing = true
        defer { isProcessing = false }
        
        do {
            let transaction = Transaction(
                userID: userID,
                type: .deposit,
                amount: amount,
                status: .completed,
                description: "Added funds to wallet"
            )
            
            // Create batch write
            let batch = db.batch()
            
            // Add transaction
            let transactionRef = db.collection("transactions").document(transaction.id)
            try batch.setData(from: transaction, forDocument: transactionRef)
            
            // Update balance
            let userRef = db.collection("users").document(userID)
            batch.updateData(["balance": FieldValue.increment(amount)], forDocument: userRef)
            
            // Commit the batch
            try await batch.commit()
            
            // Update local balance
            balance += amount
            
        } catch {
            self.error = error
            throw error
        }
    }
} 