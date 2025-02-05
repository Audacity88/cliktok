import Foundation
import FirebaseFirestore

struct User: Identifiable, Codable {
    @DocumentID var id: String?
    var username: String
    var displayName: String
    var bio: String
    var profileImageURL: String?
    var createdAt: Date
    var updatedAt: Date
    var isPrivateAccount: Bool
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName
        case bio
        case profileImageURL
        case createdAt
        case updatedAt
        case isPrivateAccount
    }
}
