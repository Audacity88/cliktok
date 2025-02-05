import Foundation
import FirebaseFirestore

struct Tip: Codable, Identifiable {
    let id: String
    let videoID: String
    let senderID: String
    let receiverID: String
    let amount: Double
    let timestamp: Date
    let transactionID: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case videoID
        case senderID
        case receiverID
        case amount
        case timestamp
        case transactionID
    }
    
    init(id: String = UUID().uuidString,
         videoID: String,
         senderID: String,
         receiverID: String,
         amount: Double,
         timestamp: Date = Date(),
         transactionID: String) {
        self.id = id
        self.videoID = videoID
        self.senderID = senderID
        self.receiverID = receiverID
        self.amount = amount
        self.timestamp = timestamp
        self.transactionID = transactionID
    }
} 