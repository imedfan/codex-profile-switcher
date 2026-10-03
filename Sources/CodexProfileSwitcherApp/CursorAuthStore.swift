import CryptoKit
import Foundation
import SQLite3

struct CursorAuthSession: Sendable {
    let accessToken: String
    let teamID: Int?
    let teamName: String?

    // Bind cached usage to the exact session without retaining credentials in the provider.
    var fingerprint: String {
        SHA256.hash(data: Data("\(accessToken)|\(teamID ?? 0)".utf8))
            .map { String(format: "%02x", $0) }.joined()
    }
}

struct CursorAuthStore: Sendable {
    let databaseURL: URL

    init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        databaseURL = home.appendingPathComponent("Library/Application Support/Cursor/User/globalStorage/state.vscdb")
    }

    func load() throws -> CursorAuthSession {
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            throw CursorUsageError.notInstalled
        }
        let values: [String: String]
        do {
            values = try readValues(immutable: false)
        } catch let error as SQLiteFailure {
            // Immutable mode ignores WAL. Only use it for a database with no sidecars.
            guard error.code == SQLITE_CANTOPEN,
                  !FileManager.default.fileExists(atPath: databaseURL.path + "-wal"),
                  !FileManager.default.fileExists(atPath: databaseURL.path + "-shm") else {
                throw CursorUsageError.databaseUnavailable
            }
            do { values = try readValues(immutable: true) }
            catch { throw CursorUsageError.databaseUnavailable }
        }
        return try session(from: values)
    }

    private func session(from values: [String: String]) throws -> CursorAuthSession {
        guard let token = values["cursorAuth/accessToken"]?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty else { throw CursorUsageError.signedOut }
        guard let cachedTeam = values["cursorAuth/cachedTeam"],
              !cachedTeam.isEmpty, cachedTeam != "null" else {
            return CursorAuthSession(accessToken: token, teamID: nil, teamName: nil)
        }
        guard let team = try? CursorUsageParser.object(Data(cachedTeam.utf8)) else {
            throw CursorUsageError.invalidTeam
        }
        guard let rawID = team["teamId"] else {
            if team.isEmpty { return CursorAuthSession(accessToken: token, teamID: nil, teamName: nil) }
            throw CursorUsageError.invalidTeam
        }
        guard let id = CursorUsageParser.number(rawID), id > 0, id < Double(Int.max), id.rounded() == id else {
            throw CursorUsageError.invalidTeam
        }
        return CursorAuthSession(accessToken: token, teamID: Int(id), teamName: team["name"] as? String)
    }

    private func readValues(immutable: Bool) throws -> [String: String] {
        var database: OpaquePointer?
        let path = immutable ? databaseURL.absoluteString + "?immutable=1" : databaseURL.path
        let flags = SQLITE_OPEN_READONLY | (immutable ? SQLITE_OPEN_URI : 0)
        let opened = sqlite3_open_v2(path, &database, flags, nil)
        defer { sqlite3_close(database) }
        guard opened == SQLITE_OK else { throw SQLiteFailure(code: opened) }
        sqlite3_busy_timeout(database, 250)
        var statement: OpaquePointer?
        let query = "SELECT key, value FROM ItemTable WHERE key IN ('cursorAuth/accessToken', 'cursorAuth/cachedTeam')"
        let prepared = sqlite3_prepare_v2(database, query, -1, &statement, nil)
        defer { sqlite3_finalize(statement) }
        guard prepared == SQLITE_OK else { throw SQLiteFailure(code: prepared) }
        var values: [String: String] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { return values }
            guard result == SQLITE_ROW else { throw SQLiteFailure(code: result) }
            guard let key = sqlite3_column_text(statement, 0),
                  let bytes = sqlite3_column_blob(statement, 1) else { continue }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            let encoding: String.Encoding = data.contains(0) ? .utf16LittleEndian : .utf8
            values[String(cString: key)] = String(data: data, encoding: encoding)
        }
    }

    private struct SQLiteFailure: Error {
        let code: Int32
    }
}
