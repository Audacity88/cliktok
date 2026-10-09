import Foundation

struct ArchiveDiscoveryItem: Identifiable, Hashable {
    let identifier: String
    let title: String
    let creator: String?
    let date: String?
    let itemDescription: String?
    let license: String
    let thumbnailURL: URL
    let mediaURL: URL
    let archiveURL: URL

    var id: String { identifier }
}

enum ArchiveLicensePolicy {
    static func isEligible(_ value: String?) -> Bool {
        guard let value else { return false }
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if ["public domain", "cc0"].contains(normalized) { return true }
        guard let url = URLComponents(string: normalized),
              ["https", "http"].contains(url.scheme ?? ""),
              url.host == "creativecommons.org", url.user == nil, url.password == nil,
              url.port == nil, url.query == nil, url.fragment == nil else { return false }
        let path = url.path.hasSuffix("/") ? String(url.path.dropLast()) : url.path
        if path == "/publicdomain/zero/1.0" { return true }
        let parts = path.split(separator: "/")
        return parts.count == 3 && parts[0] == "licenses"
            && ["by", "by-sa", "by-nc", "by-nc-sa"].contains(String(parts[1]))
            && ["1.0", "2.0", "2.5", "3.0", "4.0"].contains(String(parts[2]))
    }
}

struct ArchiveMetadataDocument: Decodable {
    struct Metadata: Decodable {
        let identifier: String
        let title: String?
        let creator: String?
        let contributor: String?
        let date: String?
        let description: String?
        let licenseURL: String?
        let rights: String?

        enum CodingKeys: String, CodingKey {
            case identifier, title, creator, contributor, date, description, rights
            case licenseURL = "licenseurl"
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            identifier = try values.decode(String.self, forKey: .identifier)
            title = values.lossyString(forKey: .title)
            creator = values.lossyString(forKey: .creator)
            contributor = values.lossyString(forKey: .contributor)
            date = values.lossyString(forKey: .date)
            description = values.lossyString(forKey: .description)
            licenseURL = values.lossyString(forKey: .licenseURL)
            rights = values.lossyString(forKey: .rights)
        }
    }

    struct File: Decodable, Equatable {
        let name: String
        let format: String?
        let source: String?

        enum CodingKeys: String, CodingKey { case name, format, source }

        init(name: String, format: String?, source: String?) {
            self.name = name
            self.format = format
            self.source = source
        }

        init(from decoder: Decoder) throws {
            let values = try decoder.container(keyedBy: CodingKeys.self)
            name = try values.decode(String.self, forKey: .name)
            format = values.lossyString(forKey: .format)
            source = values.lossyString(forKey: .source)
        }
    }

    let metadata: Metadata
    let files: [File]
}

extension KeyedDecodingContainer {
    fileprivate func lossyString(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) { return value }
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        }
        return nil
    }
}

enum ArchiveMediaSelector {
    static func compatibleFile(in files: [ArchiveMetadataDocument.File]) -> ArchiveMetadataDocument.File? {
        files
            .filter { file in
                let name = file.name.lowercased()
                let format = file.format?.lowercased() ?? ""
                return name.hasSuffix(".mp4") && file.source?.lowercased() == "derivative" &&
                    ["h.264", "512kb mpeg4", "mpeg4"].contains(format)
            }
            .sorted { lhs, rhs in score(lhs) > score(rhs) }
            .first
    }

    private static func score(_ file: ArchiveMetadataDocument.File) -> Int {
        let name = file.name.lowercased()
        var value = file.source?.lowercased() == "derivative" ? 20 : 0
        if name.contains("512kb") { value += 10 }
        if name.contains("h.264") || name.contains("h264") { value += 5 }
        if name.contains("thumb") || name.contains("sample") { value -= 20 }
        return value
    }
}
