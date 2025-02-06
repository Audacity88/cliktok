import Foundation
import FirebaseFirestore

struct User: Codable, Identifiable {
    @DocumentID var id: String?
    var username: String
    var displayName: String
    var bio: String
    var profileImageURL: String?
    var isPrivateAccount: Bool
    var balance: Double?
    
    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "displayName"
        case bio
        case profileImageURL = "profileImageURL"
        case isPrivateAccount = "isPrivateAccount"
        case balance
    }
    
    init(id: String? = nil,
         username: String,
         displayName: String,
         bio: String,
         profileImageURL: String? = nil,
         isPrivateAccount: Bool = false,
         balance: Double? = nil) {
        self.id = id
        self.username = username
        self.displayName = displayName
        self.bio = bio
        self.profileImageURL = profileImageURL
        self.isPrivateAccount = isPrivateAccount
        self.balance = balance
    }
}
