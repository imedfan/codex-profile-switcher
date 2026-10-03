import Foundation

@MainActor
final class CursorUsageProvider {
    private(set) var snapshot: CursorUsageSnapshot?
    private(set) var teamName: String?
    private(set) var error: CursorUsageError?
    private(set) var isRefreshing = false
    var onChange: (() -> Void)?

    private let loadSession: @Sendable () async throws -> CursorAuthSession
    private let fetchUsage: @Sendable (CursorAuthSession) async throws -> CursorUsageSnapshot
    private var fingerprint: String?
    private var lastAttempt: Date?
    private var task: Task<Void, Never>?

    init(
        loadSession: @escaping @Sendable () async throws -> CursorAuthSession = {
            try await Task.detached(priority: .utility) { try CursorAuthStore().load() }.value
        },
        fetchUsage: @escaping @Sendable (CursorAuthSession) async throws -> CursorUsageSnapshot = {
            try await CursorUsageClient().fetch(session: $0)
        }
    ) {
        self.loadSession = loadSession
        self.fetchUsage = fetchUsage
    }

    @discardableResult
    func refresh(force: Bool = false, now: Date = Date()) -> Task<Void, Never>? {
        guard !isRefreshing else { return task }
        if !force, let lastAttempt, now.timeIntervalSince(lastAttempt) < 60 { return nil }
        lastAttempt = now
        isRefreshing = true
        onChange?()
        task = Task { await self.performRefresh() }
        return task
    }

    private func performRefresh() async {
        defer {
            isRefreshing = false
            task = nil
            onChange?()
        }
        let session: CursorAuthSession
        do {
            session = try await loadSession()
        } catch {
            clearSession(error: error as? CursorUsageError ?? .databaseUnavailable)
            return
        }
        if fingerprint != session.fingerprint {
            snapshot = nil
            fingerprint = session.fingerprint
        }
        teamName = session.teamName
        error = nil
        onChange?()
        let result: Result<CursorUsageSnapshot, Error>
        do { result = .success(try await fetchUsage(session)) }
        catch { result = .failure(error) }
        // Recheck even failed requests: Cursor may have switched accounts in flight.
        do {
            let current = try await loadSession()
            guard current.fingerprint == session.fingerprint else {
                clearSession(error: .accountChanged)
                return
            }
        } catch {
            clearSession(error: error as? CursorUsageError ?? .databaseUnavailable)
            return
        }
        switch result {
        case .success(let snapshot):
            self.snapshot = snapshot
        case .failure(let error):
            self.error = error as? CursorUsageError ?? .network
            if self.error == .unauthorized { snapshot = nil }
        }
    }

    private func clearSession(error: CursorUsageError) {
        snapshot = nil
        teamName = nil
        fingerprint = nil
        self.error = error
    }
}
