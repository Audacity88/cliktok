import SwiftUI
import FirebaseFirestore
import StripePayments

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
        if PaymentManager.shared.isDevelopmentMode {
            let decimalAmount = NSDecimalNumber(value: amount).decimalValue
            PaymentManager.shared.addTestMoney(amount: decimalAmount)
            let currentBalance = PaymentManager.shared.getCurrentBalance()
            balance = NSDecimalNumber(decimal: currentBalance).doubleValue
        } else {
            // In production mode, we'll handle real payments here
            do {
                try await prepareTip(amount: amount)
            } catch {
                print("Failed to add funds: \(error)")
            }
        }
    }
    
    @MainActor
    func prepareTip(amount: Double) async throws {
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
            let currentBalance = paymentManager.getCurrentBalance()
            balance = NSDecimalNumber(decimal: currentBalance).doubleValue
            print("Loaded balance: $\(String(format: "%.2f", balance))")
        } else {
            guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
            
            do {
                let doc = try await db.collection("users").document(userId).getDocument()
                if let balance = doc.data()?["balance"] as? Double {
                    self.balance = balance
                }
            } catch {
                self.error = error
            }
        }
    }
    
    func loadTipHistory() async {
        guard let userId = AuthenticationManager.shared.currentUser?.uid else { return }
        
        do {
            let snapshot = try await db.collection("users")
                .document(userId)
                .collection("tips")
                .order(by: "timestamp", descending: true)
                .limit(to: 50)
                .getDocuments()
            
            self.tipHistory = snapshot.documents.compactMap { doc -> Tip? in
                let data = doc.data()
                guard let amount = data["amount"] as? Double,
                      let timestamp = data["timestamp"] as? Timestamp,
                      let videoID = data["videoID"] as? String,
                      let senderID = data["senderID"] as? String,
                      let receiverID = data["receiverID"] as? String,
                      let transactionID = data["transactionID"] as? String else {
                    return nil
                }
                return Tip(id: doc.documentID,
                          amount: amount,
                          timestamp: timestamp.dateValue(),
                          videoID: videoID,
                          senderID: senderID,
                          receiverID: receiverID,
                          transactionID: transactionID)
            }
        } catch {
            self.error = error
        }
    }
    
    // MARK: - Private Methods
    
    private func processTip(amount: Double, receiverID: String, videoID: String) async throws {
        guard let senderID = AuthenticationManager.shared.currentUser?.uid else {
            throw NSError(domain: "TipError", code: 400, userInfo: [NSLocalizedDescriptionKey: "Invalid tip amount or user"])
        }
        
        let transactionID = UUID().uuidString
        
        // Record the tip in Firestore
        let tipRef = db.collection("users").document(senderID).collection("tips").document()
        let tip = [
            "amount": amount,
            "timestamp": Timestamp(),
            "videoID": videoID,
            "senderID": senderID,
            "receiverID": receiverID,
            "transactionID": transactionID
        ] as [String : Any]
        
        try await tipRef.setData(tip)
        
        // Update recipient's balance
        let recipientRef = db.collection("users").document(receiverID)
        try await db.runTransaction { transaction, errorPointer in
            let recipientDoc: DocumentSnapshot
            do {
                try recipientDoc = transaction.getDocument(recipientRef)
            } catch let fetchError as NSError {
                errorPointer?.pointee = fetchError
                return nil
            }
            
            let currentBalance = (recipientDoc.data()?["balance"] as? Double) ?? 0
            transaction.updateData(["balance": currentBalance + amount], forDocument: recipientRef)
            return nil
        }
        
        // Refresh the UI
        await loadBalance()
        await loadTipHistory()
    }
}