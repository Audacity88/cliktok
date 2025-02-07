import Foundation
import FirebaseAuth
import FirebaseFirestore

enum UserRole: String, Codable {
    case regular
    case marketer
}

struct User: Codable, Identifiable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var bio: String
    var profileImageURL: String?
    var isPrivateAccount: Bool
    var balance: Double?
    var userRole: UserRole
    var companyName: String?
    
    var username: String {
        // Use email without domain as username
        email.components(separatedBy: "@").first ?? email
    }
    
    enum CodingKeys: String, CodingKey {
        case id
        case email
        case displayName = "displayName"
        case bio
        case profileImageURL = "profileImageURL"
        case isPrivateAccount = "isPrivateAccount"
        case balance
        case userRole = "userRole"
        case companyName = "companyName"
    }
    
    init(id: String? = nil,
         email: String,
         displayName: String,
         bio: String,
         profileImageURL: String? = nil,
         isPrivateAccount: Bool = false,
         balance: Double? = nil,
         userRole: UserRole = .regular,
         companyName: String? = nil) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.bio = bio
        self.profileImageURL = profileImageURL
        self.isPrivateAccount = isPrivateAccount
        self.balance = balance
        self.userRole = userRole
        self.companyName = companyName
    }
}
