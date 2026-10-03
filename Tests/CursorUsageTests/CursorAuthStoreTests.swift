import Foundation
import SQLite3
import XCTest
@testable import CodexProfileSwitcherApp

final class CursorAuthStoreTests: XCTestCase {
    private var home: URL!
    private var store: CursorAuthStore!
    private var database: OpaquePointer?

    override func setUpWithError() throws {
        home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        store = CursorAuthStore(home: home)
        try FileManager.default.createDirectory(at: store.databaseURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        sqlite3_close(database)
        database = nil
        try FileManager.default.removeItem(at: home)
    }

    private func create(wal: Bool = false) throws {
        XCTAssertEqual(sqlite3_open(store.databaseURL.path, &database), SQLITE_OK)
        if wal { try execute("PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;") }
        try execute("CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value BLOB)")
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
            throw NSError(domain: "SQLite fixture failed", code: 1)
        }
    }

    func testMissingDatabaseAndMissingTokenHaveActionableErrors() throws {
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? CursorUsageError, .notInstalled) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.databaseURL.path))
        try create()
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? CursorUsageError, .signedOut) }
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', '   ')")
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? CursorUsageError, .signedOut) }
    }

    func testReadsTokenAndTeamWithoutChangingDatabase() throws {
        try create()
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'fake-token'), ('cursorAuth/cachedTeam', '{\"teamId\":42,\"name\":\"Example team\"}')")
        let before = try Data(contentsOf: store.databaseURL)
        let session = try store.load()
        XCTAssertEqual(session.accessToken, "fake-token")
        XCTAssertEqual(session.teamID, 42)
        XCTAssertEqual(session.teamName, "Example team")
        XCTAssertEqual(try Data(contentsOf: store.databaseURL), before)
        XCTAssertFalse(session.fingerprint.contains("fake-token"))
        XCTAssertNotEqual(session.fingerprint, sampleSession(token: "another").fingerprint)
    }

    func testReadsUncheckpointedWALAndNewAccount() throws {
        try create(wal: true)
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'old-token')")
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.databaseURL.path + "-wal"))
        XCTAssertEqual(try store.load().accessToken, "old-token")
        try execute("UPDATE ItemTable SET value='new-token' WHERE key='cursorAuth/accessToken'")
        XCTAssertEqual(try store.load().accessToken, "new-token")
        try execute("DELETE FROM ItemTable WHERE key='cursorAuth/accessToken'")
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? CursorUsageError, .signedOut) }
    }

    func testBlobTokenAndIndividualAccount() throws {
        try create()
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', X'660061006b006500')")
        let session = try store.load()
        XCTAssertEqual(session.accessToken, "fake")
        XCTAssertNil(session.teamID)
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/cachedTeam', 'null')")
        XCTAssertNil(try store.load().teamID)
    }

    func testCorruptTeamCannotFallBackToWrongLimit() throws {
        try create()
        try execute("INSERT INTO ItemTable VALUES ('cursorAuth/accessToken', 'fake'), ('cursorAuth/cachedTeam', 'not-json')")
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? CursorUsageError, .invalidTeam) }
        try execute("UPDATE ItemTable SET value='{\"teamId\":true}' WHERE key='cursorAuth/cachedTeam'")
        XCTAssertThrowsError(try store.load()) { XCTAssertEqual($0 as? CursorUsageError, .invalidTeam) }
        try execute("UPDATE ItemTable SET value='{\"teamId\":\"42\"}' WHERE key='cursorAuth/cachedTeam'")
        XCTAssertEqual(try store.load().teamID, 42)
    }

    func testCorruptDatabaseReportsGenericError() throws {
        try Data("not a database: secret".utf8).write(to: store.databaseURL)
        XCTAssertThrowsError(try store.load()) {
            XCTAssertEqual($0 as? CursorUsageError, .databaseUnavailable)
            XCTAssertFalse($0.localizedDescription.contains("secret"))
        }
    }
}
