import Foundation

final class CursorUsageClient: Sendable {
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)
    private let transport: Transport

    init(transport: Transport? = nil) {
        self.transport = transport ?? { request in
            let configuration = URLSessionConfiguration.ephemeral
            configuration.httpCookieStorage = nil
            configuration.urlCache = nil
            let session = URLSession(configuration: configuration, delegate: CursorRedirectBlocker(), delegateQueue: nil)
            defer { session.invalidateAndCancel() }
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw CursorUsageError.invalidResponse }
            return (data, response)
        }
    }

    func fetch(session: CursorAuthSession, now: Date = Date()) async throws -> CursorUsageSnapshot {
        let periodData = try await request(
            path: "/aiserver.v1.DashboardService/GetCurrentPeriodUsage",
            token: session.accessToken, body: [:])
        let grokBotData = try? await request(
            path: "/aiserver.v1.DashboardService/GetSandUsageStatus",
            token: session.accessToken, body: [:])
        return try CursorUsageParser.snapshot(periodData, grokBotData: grokBotData, now: now)
    }

    private func request(path: String, token: String, body: [String: Any]? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api2.cursor.sh" + path)!)
        request.timeoutInterval = 20
        request.httpMethod = body == nil ? "GET" : "POST"
        request.setValue("Bearer " + token, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Connect-Protocol-Version")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        do {
            let (data, response) = try await transport(request)
            switch response.statusCode {
            case 200..<300: return data
            case 401, 403: throw CursorUsageError.unauthorized
            case 429: throw CursorUsageError.rateLimited
            default: throw CursorUsageError.server
            }
        } catch let error as CursorUsageError {
            throw error
        } catch {
            // Network and server error text can contain URLs or credentials.
            throw CursorUsageError.network
        }
    }
}

final class CursorRedirectBlocker: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
