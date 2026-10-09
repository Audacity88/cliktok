import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum ArchiveDiscoveryError: LocalizedError {
    case rateLimited
    case unavailable
    case malformedItem
    case noEligibleItems
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .rateLimited: return "Internet Archive is receiving too many requests. Please try again shortly."
        case .unavailable: return "This Archive item has no compatible playable MP4."
        case .malformedItem: return "Internet Archive returned an item we could not safely read."
        case .noEligibleItems: return "No eligible Archive videos are available right now."
        case .network: return "Internet Archive could not be reached. Check your connection and try again."
        }
    }
}

actor ArchiveDiscoveryService {
    static let shared = ArchiveDiscoveryService()

    // Intentionally small and deterministic. Every response is still re-validated.
    private let curatedIdentifiers = ["BigBuckBunny_328", "ElephantsDream", "Sintel"]
    private let session: URLSession
    private var cache: [ArchiveDiscoveryItem]?

    init(session: URLSession = .shared) { self.session = session }

    func fetchCatalog() async throws -> [ArchiveDiscoveryItem] {
        if let cache { return cache }

        var items: [ArchiveDiscoveryItem] = []
        var failure: Error?
        for identifier in curatedIdentifiers {
            do {
                if let item = try await fetchItem(identifier: identifier) { items.append(item) }
            } catch ArchiveDiscoveryError.rateLimited {
                throw ArchiveDiscoveryError.rateLimited
            } catch {
                // One malformed or unavailable curated item must not hide valid items.
                try Task.checkCancellation()
                if failure == nil { failure = error }
            }
        }
        guard !items.isEmpty else {
            if let failure { throw failure }
            throw ArchiveDiscoveryError.noEligibleItems
        }
        cache = items
        return items
    }

    private func fetchItem(identifier: String) async throws -> ArchiveDiscoveryItem? {
        guard let encoded = identifier.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://archive.org/metadata/\(encoded)") else {
            throw ArchiveDiscoveryError.malformedItem
        }
        let data: Data
        let response: URLResponse
        do { (data, response) = try await session.data(from: url) }
        catch { throw ArchiveDiscoveryError.network(error) }

        guard let http = response as? HTTPURLResponse else { throw ArchiveDiscoveryError.network(URLError(.badServerResponse)) }
        if http.statusCode == 429 { throw ArchiveDiscoveryError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw ArchiveDiscoveryError.unavailable }

        let document: ArchiveMetadataDocument
        do { document = try JSONDecoder().decode(ArchiveMetadataDocument.self, from: data) }
        catch { throw ArchiveDiscoveryError.malformedItem }

        let license = document.metadata.licenseURL ?? document.metadata.rights
        guard ArchiveLicensePolicy.isEligible(license), let license else { return nil }
        guard let file = ArchiveMediaSelector.compatibleFile(in: document.files),
              let escapedName = file.name.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let mediaURL = URL(string: "https://archive.org/download/\(encoded)/\(escapedName)"),
              let thumbnailURL = URL(string: "https://archive.org/services/img/\(encoded)"),
              let archiveURL = URL(string: "https://archive.org/details/\(encoded)") else {
            throw ArchiveDiscoveryError.unavailable
        }

        return ArchiveDiscoveryItem(
            identifier: document.metadata.identifier,
            title: document.metadata.title?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? identifier,
            creator: document.metadata.creator ?? document.metadata.contributor,
            date: document.metadata.date,
            itemDescription: document.metadata.description,
            license: license,
            thumbnailURL: thumbnailURL,
            mediaURL: mediaURL,
            archiveURL: archiveURL
        )
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
