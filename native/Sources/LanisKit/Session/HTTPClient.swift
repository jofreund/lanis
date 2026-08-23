import Foundation
import os

let httpLog = Logger(subsystem: "io.github.alessioc42.sph.native", category: "http")

/// Thin URLSession wrapper: isolated cookie jar per session, no auto-redirects,
/// user-agent injection. `LanisSession` and the login flow both use it.
final class HTTPClient: NSObject, URLSessionTaskDelegate, Sendable {
    let session: URLSession
    let cookies: HTTPCookieStorage
    let userAgent: String

    init(userAgent: String, timeout: TimeInterval) {
        let cfg = URLSessionConfiguration.ephemeral
        let storage = HTTPCookieStorage.sharedCookieStorage(forGroupContainerIdentifier: UUID().uuidString)
        cfg.httpCookieStorage = storage
        cfg.httpCookieAcceptPolicy = .always
        cfg.httpShouldSetCookies = true
        cfg.timeoutIntervalForRequest = timeout
        cfg.httpAdditionalHeaders = ["User-Agent": userAgent]
        self.cookies = storage
        self.userAgent = userAgent
        self.session = URLSession(configuration: cfg)
        super.init()
    }

    struct Response: Sendable {
        let status: Int
        let headers: [String: String]
        let body: Data
        var text: String { String(decoding: body, as: UTF8.self) }
        var location: String? { headers["Location"] ?? headers["location"] }
    }

    func head(_ url: URL) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = "HEAD"
        return try await perform(req)
    }

    func get(_ url: URL, headers: [String: String] = [:]) async throws -> Response {
        var req = URLRequest(url: url)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        return try await perform(req)
    }

    func postForm(_ url: URL, form: [String: String], headers: [String: String] = [:]) async throws -> Response {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        req.httpBody = Data(Self.encodeForm(form).utf8)
        return try await perform(req)
    }

    private func perform(_ req: URLRequest) async throws -> Response {
        do {
            // Delegate per task: refuses redirects so we can read `Location` like the Dart client.
            let (data, resp) = try await session.data(for: req, delegate: NoRedirect.shared)
            guard let http = resp as? HTTPURLResponse else { throw LanisError.network }
            var headers: [String: String] = [:]
            for (k, v) in http.allHeaderFields { headers["\(k)"] = "\(v)" }
            let cookieNames = (cookies.cookies(for: req.url!) ?? []).map { "\($0.name)@\($0.domain)" }.joined(separator: ",")
            let line = "\(req.httpMethod ?? "GET") \(req.url?.absoluteString ?? "") -> \(http.statusCode) loc=\(headers["Location"] ?? "-") bytes=\(data.count) cookies=[\(cookieNames)] setCookie=\(headers["Set-Cookie"].map { $0.replacingOccurrences(of: "=[^;,]+", with: "=…", options: .regularExpression) } ?? "-")"
            httpLog.notice("\(line, privacy: .public)")
            return Response(status: http.statusCode, headers: headers, body: data)
        } catch let e as URLError {
            switch e.code {
            case .timedOut, .notConnectedToInternet, .cannotConnectToHost, .networkConnectionLost, .dnsLookupFailed:
                throw LanisError.noConnection
            default:
                throw LanisError.unknown(e.localizedDescription)
            }
        }
    }

    static func encodeForm(_ form: [String: String]) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._*")
        return form.map { k, v in
            "\(k.addingPercentEncoding(withAllowedCharacters: allowed) ?? k)=\(v.addingPercentEncoding(withAllowedCharacters: allowed)?.replacingOccurrences(of: "%20", with: "+") ?? v)"
        }.joined(separator: "&")
    }

    /// Per-task delegate that blocks redirects.
    final class NoRedirect: NSObject, URLSessionTaskDelegate, Sendable {
        static let shared = NoRedirect()
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse,
                        newRequest request: URLRequest) async -> URLRequest? { nil }
    }
}
