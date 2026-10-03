import Foundation
import XCTest
@testable import CodexProfileSwitcherApp

final class CursorUsageTests: XCTestCase {
    private func data(_ string: String) -> Data { Data(string.utf8) }

    func testUsesIndependentPoolPercentagesWithoutInferringFromMoney() throws {
        let result = try CursorUsageParser.snapshot(data(#"{"enabled":true,"billingCycleEnd":"1790812800000","planUsage":{"autoPercentUsed":3.4,"apiPercentUsed":0,"totalSpend":645,"limit":2000,"totalPercentUsed":88}}"#), now: testNow)
        XCTAssertEqual(result.cursorModelsUsedPercent, 3)
        XCTAssertEqual(result.otherModelsUsedPercent, 0)
        XCTAssertEqual(result.periodEnd, CursorUsageParser.date("2026-10-01T00:00:00Z"))
        XCTAssertEqual(result.fetchedAt, testNow)
    }

    func testMissingAndInvalidPoolPercentagesAreNotReportedAsZero() throws {
        for value in ["null", "true", "-1", #""nan""#, #""1e999""#] {
            let json = "{\"billingCycleEnd\":\"1790812800000\",\"planUsage\":{\"autoPercentUsed\":\(value),\"apiPercentUsed\":0}}"
            XCTAssertThrowsError(try CursorUsageParser.snapshot(data(json), now: testNow), json)
        }
        for json in ["{}", "[]", "not json",
                     #"{"billingCycleEnd":"1790812800000","planUsage":{"autoPercentUsed":3}}"#,
                     #"{"billingCycleEnd":"1790812800000","planUsage":{"apiPercentUsed":0}}"#,
                     #"{"billingCycleEnd":"1790812800000","planUsage":{"totalPercentUsed":32}}"#,
                     #"{"enabled":false,"billingCycleEnd":"1790812800000","planUsage":{"autoPercentUsed":3,"apiPercentUsed":0}}"#] {
            XCTAssertThrowsError(try CursorUsageParser.snapshot(data(json), now: testNow), json)
        }
    }

    func testPercentRoundingMatchesCursorAndDisplayPreference() throws {
        for (raw, expected) in [("0", 0), ("0.01", 1), ("3.49", 3), ("3.5", 4), ("103", 100), (#""42.2""#, 42)] {
            let json = "{\"billingCycleEnd\":\"1790812800000\",\"planUsage\":{\"autoPercentUsed\":\(raw),\"apiPercentUsed\":\(raw)}}"
            let result = try CursorUsageParser.snapshot(data(json), now: testNow)
            XCTAssertEqual(result.cursorModelsUsedPercent, expected)
            XCTAssertEqual(result.otherModelsUsedPercent, expected)
            XCTAssertEqual(LimitDisplayMode.remaining.displayedPercent(forUsedPercent: result.cursorModelsUsedPercent), 100 - expected)
        }
    }

    func testResetComesFromAPIAndRejectsMissingOrExpiredDates() throws {
        for end in [#""2026-10-01T00:00:00.000Z""#, #""1790812800000""#, "1790812800000"] {
            let json = "{\"billingCycleEnd\":\(end),\"planUsage\":{\"autoPercentUsed\":3,\"apiPercentUsed\":0}}"
            let result = try CursorUsageParser.snapshot(data(json), now: testNow)
            XCTAssertEqual(result.periodEnd, Date(timeIntervalSince1970: 1790812800))
        }
        for end in ["null", "0", "true", #""invalid""#, #""2026-09-01T00:00:00Z""#] {
            let json = "{\"billingCycleEnd\":\(end),\"planUsage\":{\"autoPercentUsed\":3,\"apiPercentUsed\":0}}"
            XCTAssertThrowsError(try CursorUsageParser.snapshot(data(json), now: testNow))
        }
    }

    func testGrokBotUsageUsesItsOwnWeeklyPercentageAndReset() throws {
        let reset = Date(timeIntervalSince1970: 1790553600)
        let json = #"{"usagePercent":18.6,"nextResetTimestampUtc":"2026-09-28T00:00:00Z"}"#
        let result = try CursorUsageParser.grokBotUsage(data(json), now: testNow)
        XCTAssertEqual(result.usedPercent, 19)
        XCTAssertEqual(result.periodEnd, reset)

        for json in [
            #"{"nextResetTimestampUtc":"2026-09-28T00:00:00Z"}"#,
            #"{"usagePercent":12}"#,
            #"{"usagePercent":12,"nextResetTimestampUtc":"2026-09-01T00:00:00Z"}"#,
        ] {
            XCTAssertThrowsError(try CursorUsageParser.grokBotUsage(data(json), now: testNow))
        }
    }

    func testClientUsesSameCurrentPeriodRequestAsCursorApp() async throws {
        let recorder = RequestRecorder()
        let client = CursorUsageClient { request in
            await recorder.append(request)
            let json = request.url?.lastPathComponent == "GetSandUsageStatus"
                ? #"{"usagePercent":24,"nextResetTimestampUtc":"2026-09-28T00:00:00Z"}"#
                : #"{"billingCycleEnd":"1790812800000","planUsage":{"autoPercentUsed":3,"apiPercentUsed":0}}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await client.fetch(session: sampleSession(), now: testNow)
        XCTAssertEqual(result.cursorModelsUsedPercent, 3)
        XCTAssertEqual(result.otherModelsUsedPercent, 0)
        XCTAssertEqual(result.grokBotUsage?.usedPercent, 24)
        let requests = await recorder.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(
            requests.compactMap { $0.url?.lastPathComponent },
            ["GetCurrentPeriodUsage", "GetSandUsageStatus"])
        for request in requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer fake-token")
            XCTAssertEqual(request.timeoutInterval, 20)
            XCTAssertEqual(request.httpMethod, "POST")
            let body = try CursorUsageParser.object(XCTUnwrap(request.httpBody))
            XCTAssertTrue(body.isEmpty)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Connect-Protocol-Version"), "1")
        }
    }

    func testUnavailableGrokBotUsageDoesNotHideCursorUsage() async throws {
        let client = CursorUsageClient { request in
            if request.url?.lastPathComponent == "GetSandUsageStatus" {
                return (Data(), HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!)
            }
            let json = #"{"billingCycleEnd":"1790812800000","planUsage":{"autoPercentUsed":3,"apiPercentUsed":0}}"#
            return (Data(json.utf8), HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        }
        let result = try await client.fetch(session: sampleSession(), now: testNow)
        XCTAssertNil(result.grokBotUsage)
    }

    private var testNow: Date { Date(timeIntervalSince1970: 1790208000) }

    func testHTTPErrorsAndNetworkDetailsAreSanitized() async {
        for (code, expected) in [(401, CursorUsageError.unauthorized), (403, .unauthorized), (429, .rateLimited), (500, .server), (302, .server)] {
            let client = CursorUsageClient { request in
                (Data("secret token".utf8), HTTPURLResponse(url: request.url!, statusCode: code, httpVersion: nil, headerFields: nil)!)
            }
            do { _ = try await client.fetch(session: sampleSession()); XCTFail("Should fail") }
            catch { XCTAssertEqual(error as? CursorUsageError, expected) }
        }
        let client = CursorUsageClient { _ in
            throw NSError(domain: "secret token", code: 1, userInfo: [NSLocalizedDescriptionKey: "Bearer secret"])
        }
        do { _ = try await client.fetch(session: sampleSession()); XCTFail("Should fail") }
        catch { XCTAssertEqual(error as? CursorUsageError, .network); XCTAssertFalse(error.localizedDescription.contains("secret")) }
    }

    func testRedirectsAreRejected() {
        let request = URLRequest(url: URL(string: "https://example.com")!)
        let response = HTTPURLResponse(url: URL(string: "https://api2.cursor.sh")!, statusCode: 302, httpVersion: nil, headerFields: nil)!
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        CursorRedirectBlocker().urlSession(session, task: session.dataTask(with: request), willPerformHTTPRedirection: response, newRequest: request) {
            XCTAssertNil($0)
        }
    }
}

actor RequestRecorder {
    var requests: [URLRequest] = []
    func append(_ request: URLRequest) { requests.append(request) }
}

func sampleSession(token: String = "fake-token") -> CursorAuthSession {
    CursorAuthSession(accessToken: token, teamID: 42, teamName: "Example team")
}

func sampleSnapshot() -> CursorUsageSnapshot {
    CursorUsageSnapshot(cursorModelsUsedPercent: 3, otherModelsUsedPercent: 0,
                        grokBotUsage: CursorGrokBotUsage(
                            usedPercent: 24, periodEnd: Date(timeIntervalSince1970: 1790553600)),
                        periodEnd: Date(timeIntervalSince1970: 1790812800),
                        fetchedAt: Date(timeIntervalSince1970: 1790208000))
}
