import Foundation

struct CursorUsageSnapshot: Equatable, Sendable {
    let cursorModelsUsedPercent: Int
    let otherModelsUsedPercent: Int
    let grokBotUsage: CursorGrokBotUsage?
    let periodEnd: Date
    let fetchedAt: Date
}

struct CursorGrokBotUsage: Equatable, Sendable {
    let usedPercent: Int
    let periodEnd: Date
}

enum CursorUsageError: Error, LocalizedError, Equatable {
    case notInstalled
    case signedOut
    case accountChanged
    case databaseUnavailable
    case invalidTeam
    case unauthorized
    case rateLimited
    case network
    case server
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Open Cursor and sign in to see usage."
        case .signedOut: return "Sign in to Cursor, then refresh."
        case .accountChanged: return "Cursor account changed. Refresh to load usage."
        case .databaseUnavailable: return "Cannot read Cursor sign-in. Try refreshing."
        case .invalidTeam: return "Reopen Cursor to update team details."
        case .unauthorized: return "Cursor session expired. Sign in again."
        case .rateLimited: return "Cursor is busy. Try refreshing later."
        case .network: return "Cannot reach Cursor. Check your connection."
        case .server: return "Cursor usage is temporarily unavailable."
        case .invalidResponse: return "Cursor returned an unsupported usage response."
        }
    }
}

enum CursorUsageParser {
    static func object(_ data: Data) throws -> [String: Any] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw CursorUsageError.invalidResponse
        }
        return object
    }

    static func number(_ value: Any?) -> Double? {
        let result: Double?
        if let number = value as? NSNumber {
            guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
            result = number.doubleValue
        } else if let string = value as? String {
            result = Double(string)
        } else {
            result = nil
        }
        guard let result, result.isFinite, result >= 0 else { return nil }
        return result
    }

    static func date(_ value: Any?) -> Date? {
        if let milliseconds = number(value), milliseconds > 0, milliseconds < 253_402_300_800_000 {
            return Date(timeIntervalSince1970: milliseconds / 1000)
        }
        guard let string = value as? String else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
    }

    static func snapshot(_ data: Data, grokBotData: Data? = nil, now: Date) throws -> CursorUsageSnapshot {
        let object = try object(data)
        guard object["enabled"] as? Bool != false,
              let plan = object["planUsage"] as? [String: Any],
              let cursorModels = number(plan["autoPercentUsed"]),
              let otherModels = number(plan["apiPercentUsed"]),
              let end = date(object["billingCycleEnd"]), end > now else {
            throw CursorUsageError.invalidResponse
        }
        return CursorUsageSnapshot(
            cursorModelsUsedPercent: displayPercent(cursorModels),
            otherModelsUsedPercent: displayPercent(otherModels),
            grokBotUsage: grokBotData.flatMap { try? grokBotUsage($0, now: now) },
            periodEnd: end, fetchedAt: now)
    }

    static func grokBotUsage(_ data: Data, now: Date) throws -> CursorGrokBotUsage {
        let object = try object(data)
        guard let percent = number(object["usagePercent"]),
              let end = date(object["nextResetTimestampUtc"]), end > now else {
            throw CursorUsageError.invalidResponse
        }
        return CursorGrokBotUsage(usedPercent: displayPercent(percent), periodEnd: end)
    }

    private static func displayPercent(_ percent: Double) -> Int {
        // Match Cursor: a positive fraction below 1% is shown as 1%, not unused.
        if percent > 0, percent < 1 { return 1 }
        return Int(min(100, percent).rounded())
    }
}
