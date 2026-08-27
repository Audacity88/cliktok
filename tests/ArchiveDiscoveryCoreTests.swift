import Foundation

@main
enum ArchiveDiscoveryCoreTests {
    static func main() throws {
        let json = #"{"metadata":{"identifier":"sample","title":["A title"],"creator":"A creator","date":"1939","description":"Description","licenseurl":"https://creativecommons.org/licenses/by/4.0/"},"files":[{"name":"original.mov","format":"QuickTime","source":"original"},{"name":"sample_512kb.mp4","format":"h.264","source":"derivative"}]}"#
        let decoded = try JSONDecoder().decode(ArchiveMetadataDocument.self, from: Data(json.utf8))
        precondition(decoded.metadata.title == "A title", "array metadata should parse")
        precondition(ArchiveMediaSelector.compatibleFile(in: decoded.files)?.name == "sample_512kb.mp4", "AVPlayer-compatible derivative should win")
        precondition(ArchiveLicensePolicy.isEligible(decoded.metadata.licenseURL), "CC BY should be eligible")
        precondition(ArchiveLicensePolicy.isEligible("Public Domain"), "public domain should be eligible")
        precondition(!ArchiveLicensePolicy.isEligible(nil), "missing license should be rejected")
        precondition(!ArchiveLicensePolicy.isEligible("All rights reserved"), "restricted license should be rejected")
        precondition(ArchiveMediaSelector.compatibleFile(in: [.init(name: "stream.mkv", format: "Matroska", source: "derivative")]) == nil, "non-MP4 media should be rejected")
        print("Archive discovery core tests passed")
    }
}
