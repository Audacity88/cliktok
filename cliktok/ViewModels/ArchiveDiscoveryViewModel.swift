import Foundation

@MainActor
final class ArchiveDiscoveryViewModel: ObservableObject {
    enum State { case idle, loading, loaded([ArchiveDiscoveryItem]), empty, failed(String) }
    @Published private(set) var state: State = .idle
    private let service: ArchiveDiscoveryService

    init(service: ArchiveDiscoveryService = .shared) { self.service = service }

    func load() async {
        guard case .loading = state else {
            state = .loading
            do {
                let items = try await service.fetchCatalog()
                state = items.isEmpty ? .empty : .loaded(items)
            } catch {
                state = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
            return
        }
    }
}
