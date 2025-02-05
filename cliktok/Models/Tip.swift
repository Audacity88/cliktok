import Foundation

struct Tip: Identifiable {
    let id: String
    let amount: Double
    let timestamp: Date
    let videoID: String
    let senderID: String
    let receiverID: String
    let transactionID: String
    
    init(id: String, amount: Double, timestamp: Date, videoID: String, senderID: String, receiverID: String, transactionID: String) {
        self.id = id
        self.amount = amount
        self.timestamp = timestamp
        self.videoID = videoID
        self.senderID = senderID
        self.receiverID = receiverID
        self.transactionID = transactionID
    }
}