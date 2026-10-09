import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

@main
enum ArchiveDiscoveryCoreTests {
    static func main() async throws {
        let json = #"{"metadata":{"identifier":"sample","title":["A title"],"creator":"A creator","date":"1939","description":"Description","licenseurl":"https://creativecommons.org/licenses/by/4.0/"},"files":[{"name":"original.mov","format":"QuickTime","source":"original"},{"name":"sample_512kb.mp4","format":"h.264","source":"derivative"}]}"#
        let decoded = try JSONDecoder().decode(ArchiveMetadataDocument.self, from: Data(json.utf8))
        precondition(decoded.metadata.title == "A title", "array metadata should parse")
        precondition(ArchiveMediaSelector.compatibleFile(in: decoded.files)?.name == "sample_512kb.mp4", "AVPlayer-compatible derivative should win")
        precondition(ArchiveLicensePolicy.isEligible(decoded.metadata.licenseURL), "CC BY should be eligible")
        precondition(ArchiveLicensePolicy.isEligible("Public Domain"), "public domain should be eligible")
        precondition(!ArchiveLicensePolicy.isEligible(nil), "missing license should be rejected")
        precondition(!ArchiveLicensePolicy.isEligible("All rights reserved"), "restricted license should be rejected")
        precondition(ArchiveMediaSelector.compatibleFile(in: [.init(name: "stream.mkv", format: "Matroska", source: "derivative")]) == nil, "non-MP4 media should be rejected")
        for value in ["Not public domain; permission required", "CC0 except commercial use", "https://evil.test/creativecommons.org/licenses/by/4.0/", "https://creativecommons.org.evil.test/licenses/by/4.0/", "https://creativecommons.org/licenses/by/4.0/extra", "https://creativecommons.org/licenses/by-nd/4.0/", "No known copyright"] {
            precondition(!ArchiveLicensePolicy.isEligible(value), "ambiguous or spoofed license accepted: \(value)")
        }
        for value in [" CC0 ", "https://creativecommons.org/publicdomain/zero/1.0/", "http://creativecommons.org/licenses/by-sa/3.0/"] {
            precondition(ArchiveLicensePolicy.isEligible(value), "explicit license rejected")
        }
        for file in [
            ArchiveMetadataDocument.File(name: "original.mp4", format: "h.264", source: "original"),
            .init(name: "stream.mp4", format: "h.264", source: "stream"),
            .init(name: "unknown.mp4", format: nil, source: "derivative"),
            .init(name: "unknown.mp4", format: "h.264", source: nil),
            .init(name: "unknown.mp4", format: "not h.264", source: "derivative")
        ] {
            precondition(ArchiveMediaSelector.compatibleFile(in: [file]) == nil, "unsafe file accepted")
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }

        StubProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await ArchiveDiscoveryService(session: session).fetchCatalog()
            preconditionFailure("offline catalog should fail")
        } catch ArchiveDiscoveryError.network { }

        StubProtocol.handler = { _ in (200, Data(json.replacingOccurrences(of: "https://creativecommons.org/licenses/by/4.0/", with: "All rights reserved").utf8)) }
        do {
            _ = try await ArchiveDiscoveryService(session: session).fetchCatalog()
            preconditionFailure("ineligible catalog should be empty")
        } catch ArchiveDiscoveryError.noEligibleItems { }

        StubProtocol.handler = { request in
            if request.url!.lastPathComponent == "BigBuckBunny_328" { return (200, Data(json.utf8)) }
            throw URLError(.timedOut)
        }
        let partial = try await ArchiveDiscoveryService(session: session).fetchCatalog()
        precondition(partial.count == 1, "one failed item must not hide a valid item")

        StubProtocol.handler = { _ in (429, Data()) }
        do {
            _ = try await ArchiveDiscoveryService(session: session).fetchCatalog()
            preconditionFailure("rate limit should fail")
        } catch ArchiveDiscoveryError.rateLimited { }

        StubProtocol.handler = { _ in (200, Data("invalid JSON".utf8)) }
        do {
            _ = try await ArchiveDiscoveryService(session: session).fetchCatalog()
            preconditionFailure("malformed catalog should fail")
        } catch ArchiveDiscoveryError.malformedItem { }
        print("Archive discovery core tests passed")
    }
}
