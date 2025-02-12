import Foundation

enum Configuration {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = ProcessInfo.processInfo.environment[key] else {
            #if DEBUG
            print("⚠️ Missing configuration value for key: \(key)")
            #endif
            throw Error.missingKey
        }

        guard let value = T(object) else {
            throw Error.invalidValue
        }

        return value
    }

    static func apiKey(for service: String) throws -> String {
        try value(for: service)
    }
}

// MARK: - API Keys
extension Configuration {
    static var openAIApiKey: String {
        get throws {
            try apiKey(for: "OPENAI_API_KEY")
        }
    }
    
    static var stripeSecretKey: String {
        get throws {
            try apiKey(for: "STRIPE_SECRET_KEY")
        }
    }
    
    static var stripePublishableKey: String {
        get throws {
            try apiKey(for: "STRIPE_PUBLISHABLE_KEY")
        }
    }
} 