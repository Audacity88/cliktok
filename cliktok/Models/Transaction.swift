import Foundation
import FirebaseFirestore

struct Transaction: Codable, Identifiable {
    let id: String
    let userID: String
    let type: TransactionType
    let amount: Double
    let status: TransactionStatus
    let timestamp: Date
    let description: String
    
    enum TransactionType: String, Codable {
        case tip
        case deposit
        case withdrawal
    }
    
    enum TransactionStatus: String, Codable {
        case pending
        case completed
        case failed
    }
    
    init(id: String = UUID().uuidString,
         userID: String,
         type: TransactionType,
         amount: Double,
         status: TransactionStatus = .pending,
         timestamp: Date = Date(),
         description: String) {
        self.id = id
        self.userID = userID
        self.type = type
        self.amount = amount
        self.status = status
        self.timestamp = timestamp
        self.description = description
    }
} 