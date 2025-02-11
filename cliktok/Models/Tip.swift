import Foundation
import FirebaseFirestore

struct Tip: Identifiable, Codable {
    @DocumentID var id: String?
    let amount: Double
    let timestamp: Date
    let videoID: String
    let senderID: String
    let receiverID: String
    let transactionID: String
    
    enum CodingKeys: String, CodingKey {
        case id
        case amount
        case timestamp
        case videoID
        case senderID
        case receiverID
        case transactionID
    }
    
    init(id: String? = nil, amount: Double, timestamp: Date, videoID: String, senderID: String, receiverID: String, transactionID: String) {
        self.id = id
        self.amount = amount
        self.timestamp = timestamp
        self.videoID = videoID
        self.senderID = senderID
        self.receiverID = receiverID
        self.transactionID = transactionID
    }
}