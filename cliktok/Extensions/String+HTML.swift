import Foundation

extension String {
    /// Removes HTML tags and decodes HTML entities from a string
    func cleaningHTMLTags() -> String {
        // Remove HTML tags using regular expressions
        let regex = try? NSRegularExpression(pattern: "<[^>]+>", options: .caseInsensitive)
        let range = NSRange(location: 0, length: self.utf16.count)
        let cleanedText = regex?.stringByReplacingMatches(in: self, options: [], range: range, withTemplate: "")
        
        // Decode HTML entities and return cleaned text
        return cleanedText?
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? self
    }
} 