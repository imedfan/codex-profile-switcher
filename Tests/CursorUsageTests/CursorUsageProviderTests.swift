import XCTest
@testable import CodexProfileSwitcherApp

@MainActor
final class CursorUsageProviderTests: XCTestCase {
    func testSuccessfulRefreshAndSameAccountFailureMarkCachedUsage() async {
        let fixture = ProviderFixture()
        let provider = makeProvider(fixture)
        await provider.refresh(force: true)?.value
        XCTAssertEqual(provider.snapshot, sampleSnapshot())
        XCTAssertNil(provider.error)
        XCTAssertFalse(provider.isRefreshing)
        await fixture.failFetch(.network)
        await provider.refresh(force: true)?.value
        XCTAssertEqual(provider.snapshot, sampleSnapshot())
        XCTAssertEqual(provider.error, .network)
        await fixture.failFetch(nil)
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.error)
    }

    func testAccountChangeAndLogoutClearOldUsage() async {
        let fixture = ProviderFixture()
        let provider = makeProvider(fixture)
        await provider.refresh(force: true)?.value
        await fixture.changeSession(sampleSession(token: "other-account"))
        await fixture.failFetch(.network)
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.snapshot)
        XCTAssertEqual(provider.error, .network)
        await fixture.failLoad(.signedOut)
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.snapshot)
        XCTAssertNil(provider.teamName)
        XCTAssertEqual(provider.error, .signedOut)
    }

    func testAccountChangeDuringFetchDiscardsResult() async {
        let fixture = ProviderFixture()
        let provider = CursorUsageProvider(loadSession: { try await fixture.load() }, fetchUsage: { _ in
            await fixture.changeSession(sampleSession(token: "new-account"))
            return sampleSnapshot()
        })
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.snapshot)
        XCTAssertEqual(provider.error, .accountChanged)
    }

    func testFailedRequestAfterAccountChangeDiscardsCachedUsage() async {
        let fixture = ProviderFixture()
        let provider = CursorUsageProvider(loadSession: { try await fixture.load() }, fetchUsage: { _ in
            try await fixture.fetch()
        })
        await provider.refresh(force: true)?.value
        await fixture.changeAccountOnFetch()
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.snapshot)
        XCTAssertNil(provider.teamName)
        XCTAssertEqual(provider.error, .accountChanged)
    }

    func testDatabaseFailureAfterRequestClearsCachedUsage() async {
        let fixture = ProviderFixture()
        let provider = CursorUsageProvider(loadSession: { try await fixture.load() }, fetchUsage: { _ in
            await fixture.failLoad(.databaseUnavailable)
            return sampleSnapshot()
        })
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.snapshot)
        XCTAssertEqual(provider.error, .databaseUnavailable)
    }

    func testExpiredSessionClearsOldUsage() async {
        let fixture = ProviderFixture()
        let provider = makeProvider(fixture)
        await provider.refresh(force: true)?.value
        await fixture.failFetch(.unauthorized)
        await provider.refresh(force: true)?.value
        XCTAssertNil(provider.snapshot)
        XCTAssertEqual(provider.error, .unauthorized)
    }

    func testRefreshCoalescesAndThrottlesButAllowsManualRetry() async {
        let fixture = ProviderFixture()
        let provider = makeProvider(fixture)
        let now = Date()
        let first = provider.refresh(now: now)
        XCTAssertTrue(provider.isRefreshing)
        let second = provider.refresh(force: true, now: now)
        await first?.value
        await second?.value
        let firstCount = await fixture.fetchCount
        XCTAssertEqual(firstCount, 1)
        XCTAssertNil(provider.refresh(now: now.addingTimeInterval(30)))
        await provider.refresh(force: true, now: now.addingTimeInterval(30))?.value
        await provider.refresh(now: now.addingTimeInterval(91))?.value
        let finalCount = await fixture.fetchCount
        XCTAssertEqual(finalCount, 3)
    }

    private func makeProvider(_ fixture: ProviderFixture) -> CursorUsageProvider {
        CursorUsageProvider(loadSession: { try await fixture.load() }, fetchUsage: { _ in try await fixture.fetch() })
    }
}

actor ProviderFixture {
    private var session = sampleSession()
    private var loadError: CursorUsageError?
    private var fetchError: CursorUsageError?
    private var changesAccountOnFetch = false

    func changeAccountOnFetch() { changesAccountOnFetch = true }
    private(set) var fetchCount = 0

    func changeSession(_ session: CursorAuthSession) { self.session = session }
    func failLoad(_ error: CursorUsageError?) { loadError = error }
    func failFetch(_ error: CursorUsageError?) { fetchError = error }
    func load() throws -> CursorAuthSession {
        if let loadError { throw loadError }
        return session
    }
    func fetch() throws -> CursorUsageSnapshot {
        fetchCount += 1
        if changesAccountOnFetch {
            session = sampleSession(token: "changed-in-flight")
            throw CursorUsageError.network
        }
        if let fetchError { throw fetchError }
        return sampleSnapshot()
    }
}
