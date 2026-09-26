import Foundation
import Darwin

nonisolated enum PluginAPIError: LocalizedError, Sendable {
    case notConfigured(String)
    case invalidEndpoint(String)
    case invalidResponse
    case authentication
    case balance
    case sensitiveInput(String)
    case malformedCredential
    case responseTooLarge
    case http(Int, String)
    case decoding(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured(let plugin):
            "\(plugin) is enabled but not fully configured."
        case .invalidEndpoint(let reason):
            "Invalid plugin server address: \(reason)"
        case .invalidResponse:
            "The plugin server returned an invalid response."
        case .authentication:
            "The plugin server rejected the saved API key."
        case .balance:
            "The plugin account has no available credit."
        case .sensitiveInput(let field):
            "Refused to send a plugin field that looks like a credential or secret: \(field)."
        case .malformedCredential:
            "The saved plugin API credential is malformed."
        case .responseTooLarge:
            "The plugin response exceeded the app's safety limit."
        case .http(let status, let detail):
            let clean = detail.trimmingCharacters(in: .whitespacesAndNewlines)
            return clean.isEmpty
                ? "The plugin server returned HTTP \(status)."
                : "The plugin server returned HTTP \(status): \(String(PluginAPIClient.sanitizeAndTruncate(clean, limit: 1_000).prefix(300)))"
        case .decoding(let detail):
            "The plugin response could not be read: \(detail)"
        }
    }
}

/// Redirects are disabled for every plugin request. Authenticated calls must not
/// bounce a key to another origin, and provider-issued artifact URLs must not turn
/// into a device-side request to an arbitrary redirect target.
private final class PluginRedirectPolicy: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

/// Small, shared HTTP transport for optional BrowserAct and Crawl4AI adapters.
/// It deliberately knows nothing about either service's credentials or payloads.
@MainActor
final class PluginAPIClient: @unchecked Sendable {
    enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case put = "PUT"
    }

    struct Response: Sendable {
        let data: Data
        let statusCode: Int
        let mimeType: String
        let suggestedFileName: String?
    }

    private let session: URLSession
    private let redirectPolicy: PluginRedirectPolicy?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            self.redirectPolicy = nil
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 300
            configuration.timeoutIntervalForResource = 330
            configuration.waitsForConnectivity = false
            configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
            configuration.urlCache = nil
            // A plugin call must never inherit a WebKit or URLSession credential
            // store. The bearer header is the only credential this transport uses.
            configuration.httpCookieStorage = nil
            configuration.httpShouldSetCookies = false
            configuration.httpCookieAcceptPolicy = .never
            configuration.urlCredentialStorage = nil
            let policy = PluginRedirectPolicy()
            self.redirectPolicy = policy
            self.session = URLSession(configuration: configuration, delegate: policy, delegateQueue: nil)
        }
    }

    func request(
        baseURL: String,
        path: String,
        method: Method = .get,
        queryItems: [URLQueryItem] = [],
        jsonBody: [String: Any]? = nil,
        bearerToken: String,
        timeout: TimeInterval = 60,
        maximumResponseBytes: Int = 20_000_000
    ) async throws -> Response {
        guard !bearerToken.isEmpty,
              bearerToken.count <= 4_096,
              bearerToken.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              bearerToken.rangeOfCharacter(from: .controlCharacters) == nil
        else { throw PluginAPIError.malformedCredential }
        let url = try Self.endpointURL(baseURL: baseURL, path: path, queryItems: queryItems)
        guard url.scheme?.lowercased() == "https" else {
            throw PluginAPIError.invalidEndpoint("authenticated plugin requests require HTTPS")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.timeoutInterval = min(max(timeout.isFinite ? timeout : 60, 5), 300)
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let jsonBody {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: jsonBody, options: [])
        }

        let started = Date()
        do {
            let hardLimit = min(max(maximumResponseBytes, 1_024), 50_000_000)
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  let finalURL = http.url,
                  finalURL.scheme?.lowercased() == url.scheme?.lowercased(),
                  finalURL.host == url.host,
                  finalURL.port == url.port,
                  finalURL.user == nil,
                  finalURL.password == nil
            else {
                throw PluginAPIError.invalidEndpoint("authenticated plugin redirects are not allowed")
            }
            let success = (200..<300).contains(http.statusCode)
            let readLimit = success ? hardLimit : min(hardLimit, 65_536)
            let data = try await Self.readBounded(
                bytes,
                maximumBytes: readLimit,
                expectedContentLength: http.expectedContentLength
            )
            try Task.checkCancellation()
            let elapsed = Date().timeIntervalSince(started)
            AppLog.plugin.info(
                "Plugin request: host=\(url.host ?? "unknown", privacy: .private), method=\(method.rawValue, privacy: .public), status=\(http.statusCode, privacy: .public), bytes=\(data.count, privacy: .public), elapsed=\(String(format: "%.2fs", elapsed), privacy: .public)"
            )

            guard (200..<300).contains(http.statusCode) else {
                if (300..<400).contains(http.statusCode) {
                    throw PluginAPIError.invalidEndpoint("authenticated plugin redirects are not allowed")
                }
                if http.statusCode == 401 {
                    throw PluginAPIError.authentication
                }
                if http.statusCode == 402 {
                    throw PluginAPIError.balance
                }
                let detail = String(Self.sanitizeAndTruncate(Self.serverMessage(from: data), limit: 1_000).prefix(300))
                throw PluginAPIError.http(http.statusCode, detail)
            }
            return Response(
                data: data,
                statusCode: http.statusCode,
                mimeType: http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first.map(String.init) ?? "application/octet-stream",
                suggestedFileName: http.suggestedFilename
            )
        } catch let error as PluginAPIError {
            if case .responseTooLarge = error {
                AppLog.plugin.warning("Plugin response rejected: host=\(url.host ?? "unknown", privacy: .private), reason=response_too_large")
            }
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            let safeError = Self.sanitizeAndTruncate(error.localizedDescription, limit: 500)
            AppLog.plugin.error("Plugin network failed: host=\(url.host ?? "unknown", privacy: .private), error=\(safeError, privacy: .private)")
            throw error
        }
    }

    /// Downloads a provider-issued artifact URL without forwarding the provider's
    /// API credential to its CDN. Used only for HTTPS output-file links returned
    /// inside an already-approved task result.
    func download(
        absoluteURL: String,
        timeout: TimeInterval = 60,
        maximumResponseBytes: Int = 25_000_000
    ) async throws -> Response {
        let clean = absoluteURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard clean.count <= 16_384,
              clean.rangeOfCharacter(from: .controlCharacters) == nil,
              !clean.contains("\\"),
              let url = URL(string: clean),
              url.scheme?.lowercased() == "https",
              let host = url.host,
              Self.isPublicNetworkHost(host),
              url.user == nil,
              url.password == nil
        else { throw PluginAPIError.invalidEndpoint("artifact URLs must be HTTPS without embedded credentials") }
        guard await Self.hasOnlyPublicDNSAddresses(host) else {
            throw PluginAPIError.invalidEndpoint("artifact host did not resolve exclusively to public addresses")
        }
        try Task.checkCancellation()

        var request = URLRequest(url: url)
        request.httpMethod = Method.get.rawValue
        request.timeoutInterval = min(max(timeout.isFinite ? timeout : 60, 5), 90)
        request.setValue("application/octet-stream, */*", forHTTPHeaderField: "Accept")
        let started = Date()
        do {
            let (bytes, response) = try await session.bytes(for: request)
            guard let http = response as? HTTPURLResponse,
                  let finalURL = http.url,
                  finalURL.scheme?.lowercased() == "https",
                  let finalHost = finalURL.host,
                  finalHost.caseInsensitiveCompare(host) == .orderedSame,
                  (finalURL.port ?? 443) == (url.port ?? 443),
                  Self.isPublicNetworkHost(finalHost),
                  finalURL.user == nil,
                  finalURL.password == nil
            else {
                throw PluginAPIError.invalidEndpoint("artifact redirect left the allowed HTTPS origin")
            }
            let hardLimit = min(max(maximumResponseBytes, 1_024), 25_000_000)
            let readLimit = (200..<300).contains(http.statusCode) ? hardLimit : min(hardLimit, 65_536)
            let data = try await Self.readBounded(
                bytes,
                maximumBytes: readLimit,
                expectedContentLength: http.expectedContentLength
            )
            try Task.checkCancellation()
            AppLog.plugin.info(
                "Plugin artifact request: host=\(url.host ?? "unknown", privacy: .private), status=\(http.statusCode, privacy: .public), bytes=\(data.count, privacy: .public), elapsed=\(String(format: "%.2fs", Date().timeIntervalSince(started), privacy: .public))"
            )
            guard (200..<300).contains(http.statusCode) else {
                if (300..<400).contains(http.statusCode) {
                    throw PluginAPIError.invalidEndpoint("artifact redirects are not allowed")
                }
                let detail = String(Self.sanitizeAndTruncate(Self.serverMessage(from: data), limit: 1_000).prefix(300))
                throw PluginAPIError.http(http.statusCode, detail)
            }
            // Re-check after the response as a defense-in-depth signal. It does
            // not pin the address used by URLSession, but catches a changed DNS
            // answer before the artifact is handed to the caller.
            guard await Self.hasOnlyPublicDNSAddresses(host) else {
                throw PluginAPIError.invalidEndpoint("artifact host changed to a non-public address")
            }
            return Response(
                data: data,
                statusCode: http.statusCode,
                mimeType: http.value(forHTTPHeaderField: "Content-Type")?.split(separator: ";").first.map(String.init) ?? "application/octet-stream",
                suggestedFileName: http.suggestedFilename
            )
        } catch let error as PluginAPIError {
            throw error
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch {
            throw error
        }
    }

    /// Reads an async response with a hard ceiling. Checking only after
    /// `URLSession.data(for:)` would still allow an untrusted endpoint to force an
    /// unbounded in-memory allocation before the app could reject it.
    /// Reads a response body under a hard byte ceiling. This is `nonisolated`
    /// on purpose: `URLSession.AsyncBytes` suspends on every chunk, so a
    /// MainActor-isolated reader turns a 25 MB artifact download into tens of
    /// millions of main-actor hops and stalls the UI.
    nonisolated private static func readBounded(
        _ bytes: URLSession.AsyncBytes,
        maximumBytes: Int,
        expectedContentLength: Int64
    ) async throws -> Data {
        guard expectedContentLength <= Int64(maximumBytes) else {
            throw PluginAPIError.responseTooLarge
        }
        var data = Data()
        let expected = expectedContentLength > 0 ? Int(min(expectedContentLength, Int64(maximumBytes))) : 0
        data.reserveCapacity(min(maximumBytes, max(64 * 1024, min(expected, 4 * 1024 * 1024))))
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < maximumBytes else { throw PluginAPIError.responseTooLarge }
            data.append(byte)
        }
        return data
    }

    /// Builds a URL while preserving any path prefix on a reverse-proxied server.
    /// Query strings in the configured base URL are rejected so a pasted tracking
    /// URL cannot silently redirect API calls.
    nonisolated static func endpointURL(baseURL: String, path: String, queryItems: [URLQueryItem] = []) throws -> URL {
        var cleanBase = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while cleanBase.hasSuffix("/") { cleanBase.removeLast() }
        guard !cleanBase.isEmpty else { throw PluginAPIError.invalidEndpoint("the address is empty") }
        guard !cleanBase.contains("\\") else {
            throw PluginAPIError.invalidEndpoint("the server address contains an unsafe backslash")
        }
        guard let base = URL(string: cleanBase),
              let baseScheme = base.scheme?.lowercased(),
              baseScheme == "https",
              base.host != nil,
              base.user == nil,
              base.password == nil,
              base.query == nil,
              base.fragment == nil
        else {
            throw PluginAPIError.invalidEndpoint("use a full HTTPS server address without a query or fragment")
        }

        let cleanPath = path.isEmpty ? "" : (path.hasPrefix("/") ? path : "/\(path)")
        guard var components = URLComponents(string: cleanBase + cleanPath) else {
            throw PluginAPIError.invalidEndpoint("the server path is invalid")
        }
        if !queryItems.isEmpty { components.queryItems = queryItems }
        guard let url = components.url else {
            throw PluginAPIError.invalidEndpoint("the server path is invalid")
        }
        return url
    }

    /// Percent-encodes a nested page URL for Crawl4AI's `/llm/{url:path}` route
    /// without turning its own query string into the API request's query string.
    nonisolated static func nestedPagePath(_ rawURL: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        // A pre-encoded `%2F` must stay literal until the remote path converter
        // decodes the complete nested URL exactly once.
        allowed.remove(charactersIn: "?#%")
        return rawURL.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// Escapes one provider identifier before it is interpolated into an API
    /// path. BrowserAct IDs are normally numeric, but a malformed model argument
    /// still must not be able to rewrite the route.
    nonisolated static func safePathComponent(_ raw: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_~")
        return raw.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
    }

    /// Converts snake, kebab, dotted, and camelCase field names into one
    /// conservative snake-case key for output omission and request validation.
    nonisolated static func normalizedFieldName(_ raw: String) -> String {
        let characters = Array(raw)
        var result = ""
        for (index, character) in characters.enumerated() {
            if character.isUppercase, index > 0 {
                let previous = characters[index - 1]
                let nextIsLowercase = index + 1 < characters.count && characters[index + 1].isLowercase
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLowercase) {
                    result.append("_")
                }
            }
            if character == "-" || character == " " || character == "." {
                if !result.hasSuffix("_") { result.append("_") }
            } else {
                result.append(contentsOf: character.lowercased())
            }
        }
        while result.contains("__") {
            result = result.replacingOccurrences(of: "__", with: "_")
        }
        return result.trimmingCharacters(in: CharacterSet(charactersIn: "_"))
    }

    /// Produces a bounded decoding probe for request validation and redaction.
    /// Percent escapes and the common numeric/named HTML entity spellings are
    /// decoded in separate passes so mixed forms such as `https&#58;&#47;/host`
    /// cannot bypass the URL and credential checks. The probe is never used as
    /// the destination sent on the wire.
    nonisolated static func canonicalizeRemoteText(_ text: String) -> String {
        // Output callers cap well below this bound; limiting the probe keeps a
        // hostile multi-megabyte response from multiplying memory during three
        // decode passes. A longer input is safely represented by its prefix.
        let source = text.count > 1_000_000 ? String(text.prefix(1_000_000)) : text
        var current = source
        let entityReplacements: [(String, String)] = [
            (#"(?i)&#(?:0*58|x0*3a);"#, ":"),
            (#"(?i)&#(?:0*47|x0*2f);"#, "/"),
            (#"(?i)&colon;"#, ":"),
            (#"(?i)&sol;"#, "/"),
            // Assignment, whitespace, and list separators. Without these,
            // `password&#61;SECRET` and `Bearer&#32;eyJ...` carry no literal
            // `=`, `:`, or space and would pass every credential pattern.
            (#"(?i)&#(?:0*3d|x0*3d);"#, "="),
            (#"(?i)&equals;"#, "="),
            (#"(?i)&#(?:0*20|x0*20);"#, " "),
            (#"(?i)&nbsp;|&#(?:0*a0|x0*a0);"#, " "),
            (#"(?i)&#(?:0*2c|x0*2c);"#, ","),
            (#"(?i)&comma;"#, ","),
        ]
        for _ in 0..<3 {
            var next = current
            for (pattern, replacement) in entityReplacements {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                let matches = expression.matches(
                    in: next,
                    range: NSRange(next.startIndex..., in: next)
                )
                for match in matches.reversed() {
                    guard let range = Range(match.range, in: next) else { continue }
                    next.replaceSubrange(range, with: replacement)
                }
            }
            if let decoded = next.removingPercentEncoding, decoded != next {
                next = decoded
            }
            if next == current { break }
            current = next
        }
        return current
    }

    /// Literal/private-address policy used before page destinations or unsigned
    /// artifact requests are sent. DNS names still must be enforced by the remote
    /// Crawl4AI/BrowserAct egress boundary; this prevents obvious literal targets.
    nonisolated static func isPublicNetworkHost(_ rawHost: String) -> Bool {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty,
              !host.contains("%"),
              !host.contains(" "),
              !host.contains("\\")
        else { return false }

        let reservedSuffixes = [
            ".localhost", ".local", ".localdomain", ".lan", ".internal", ".home", ".home.arpa",
            ".arpa", ".invalid", ".test", ".example", ".onion",
        ]
        if reservedSuffixes.contains(where: { host == String($0.dropFirst()) || host.hasSuffix($0) }) {
            return false
        }
        if host == "localhost" { return false }

        let decimalParts = host.split(separator: ".", omittingEmptySubsequences: false)
        if let firstLabel = decimalParts.first {
            let lowerLabel = String(firstLabel).lowercased()
            if lowerLabel.hasPrefix("0x") || lowerLabel.hasPrefix("0o") || lowerLabel.hasPrefix("0b") {
                return false
            }
        }
        if decimalParts.count == 4 {
            let labels = decimalParts.map { String($0) }
            if labels.allSatisfy({ label in
                label.allSatisfy { character in character.isNumber }
            }) {
                // Reject non-canonical numeric forms such as 0177.0.0.1. Some
                // URL/network parsers interpret those as a different address.
                guard labels.allSatisfy({ $0.count <= 3 && ($0.count == 1 || !$0.hasPrefix("0")) }),
                      let octets = labels.compactMap({ UInt8($0) }),
                      octets.count == 4
                else { return false }
                return isPublicIPv4(octets)
            }
        }
        if !decimalParts.isEmpty, decimalParts.allSatisfy({ part in
            part.allSatisfy { character in character.isNumber }
        }) {
            return false
        }
        if host.contains(":") {
            return isPublicIPv6(host)
        }
        if !host.contains(".") || host.allSatisfy({ $0.isNumber }) { return false }

        // URL parsers and DNS resolvers disagree about malformed hostname
        // syntax. Keep this final literal check conservative so alternate forms
        // cannot smuggle a loopback or metadata address through the policy.
        let labels = host.split(separator: ".", omittingEmptySubsequences: false)
        guard labels.allSatisfy({ label in
            guard !label.isEmpty, label.first != "-", label.last != "-" else { return false }
            return label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
        }) else { return false }
        return true
    }

    nonisolated private static func resolvedAddressLiterals(for host: String) -> [String] {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            // SOCK_STREAM is 1 on Darwin; use the integer literal to avoid
            // importing a platform-specific enum type into the async path.
            ai_socktype: 1,
            ai_protocol: 0,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result else { return [] }
        defer { freeaddrinfo(first) }
        var addresses: [String] = []
        var cursor: UnsafeMutablePointer<addrinfo>? = first
        while let info = cursor?.pointee {
            if let socketAddress = info.ai_addr {
                if info.ai_family == AF_INET {
                    var address = socketAddress.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                        $0.pointee.sin_addr
                    }
                    var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                    if inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                        addresses.append(String(cString: buffer))
                    }
                } else if info.ai_family == AF_INET6 {
                    var address = socketAddress.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) {
                        $0.pointee.sin6_addr
                    }
                    var buffer = [CChar](repeating: 0, count: Int(INET6_ADDRSTRLEN))
                    if inet_ntop(AF_INET6, &address, &buffer, socklen_t(INET6_ADDRSTRLEN)) != nil {
                        addresses.append(String(cString: buffer))
                    }
                }
            }
            cursor = info.ai_next
        }
        return addresses
    }

    nonisolated private static func hasOnlyPublicDNSAddresses(_ host: String) async -> Bool {
        guard !Task.isCancelled else { return false }
        // `getaddrinfo` is a blocking libc call and cannot be interrupted once
        // it starts. The child is cancelled for the surrounding request, and
        // the result is discarded if the caller has already been cancelled;
        // the remote service's egress policy remains the hard DNS boundary.
        let lookup = Task.detached(priority: .utility) {
            Self.resolvedAddressLiterals(for: host)
        }
        let addresses = await withTaskCancellationHandler {
            await lookup.value
        } onCancel: {
            lookup.cancel()
        }
        guard !Task.isCancelled, !addresses.isEmpty else { return false }
        return addresses.allSatisfy { Self.isPublicNetworkHost($0) }
    }

    nonisolated private static func isPublicIPv4(_ octets: [UInt8]) -> Bool {
        let a = Int(octets[0]), b = Int(octets[1]), c = Int(octets[2]), d = Int(octets[3])
        if a == 0 || a == 10 || a == 127 || a >= 224 { return false }
        if a == 100 && (64...127).contains(b) { return false }
        if a == 169 && b == 254 { return false }
        if a == 172 && (16...31).contains(b) { return false }
        if a == 192 && b == 168 { return false }
        if a == 192 && b == 0 && (c == 0 || c == 2) { return false }
        if a == 192 && b == 88 && c == 99 { return false }
        if a == 198 && (b == 18 || b == 19) { return false }
        if a == 198 && b == 51 && c == 100 { return false }
        if a == 203 && b == 0 && c == 113 { return false }
        return !(a == 255 && b == 255 && c == 255 && d == 255)
    }

    nonisolated private static func isPublicIPv6(_ rawHost: String) -> Bool {
        var host = rawHost.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if host.hasPrefix("["), host.hasSuffix("]") {
            host.removeFirst()
            host.removeLast()
        }
        while host.hasSuffix(".") { host.removeLast() }
        guard !host.isEmpty, !host.contains("%") else { return false }

        var address = in6_addr()
        let parsed = host.withCString { inet_pton(AF_INET6, $0, &address) }
        guard parsed == 1 else { return false }
        let bytes = withUnsafeBytes(of: &address) { Array($0) }
        guard bytes.count == 16 else { return false }

        if bytes.allSatisfy({ $0 == 0 }) { return false }
        if bytes[0..<15].allSatisfy({ $0 == 0 }) && bytes[15] == 1 { return false }

        // IPv4-mapped addresses must be judged by their embedded IPv4 value.
        let mapped = bytes[0..<10].allSatisfy { $0 == 0 } && bytes[10] == 0xff && bytes[11] == 0xff
        if mapped {
            return isPublicIPv4(Array(bytes[12..<16]))
        }
        // IPv4-compatible and other ::/96 forms are reserved rather than public.
        if bytes[0..<12].allSatisfy({ $0 == 0 }) { return false }

        let first = (UInt16(bytes[0]) << 8) | UInt16(bytes[1])
        let second = (UInt16(bytes[2]) << 8) | UInt16(bytes[3])
        if (0xfc00...0xfdff).contains(first) { return false }
        // fe80 link-local, fec0 site-local, fe00 reserved, and ff multicast
        // are all unsuitable destinations for a page or artifact fetch.
        if (0xfe00...0xffff).contains(first) { return false }
        if first == 0x2001 && (second == 0 || second == 0x0002 || second == 0x0db8) { return false }
        if first == 0x2001 && ((0x0010...0x001f).contains(second) || (0x0020...0x002f).contains(second)) { return false }
        if first == 0x2002 { return false }
        if first == 0x0064 && second == 0xff9b { return false } // 64:ff9b::/96
        // 100::/64 is reserved/discard-only. Check the whole /64 prefix rather
        // than only the second hextet, which would let 100:0:1::1 through.
        if first == 0x0064 && bytes[2..<8].allSatisfy({ $0 == 0 }) { return false }
        return true
    }

    /// Extracts absolute or protocol-relative HTTP(S) URLs from free text. The
    /// request validator uses this to reject signed/credential-bearing links even
    /// when they are nested in a configuration value or JavaScript snippet.
    nonisolated static func httpURLs(in text: String) -> [URL] {
        let patterns = [
            #"(?i)https?://[^\s<>"'`]+"#,
            #"(?i)(?<![A-Za-z0-9:])//[^\s<>"'`]+"#,
        ]
        var result: [URL] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            for match in expression.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text),
                      let url = URL(string: String(text[swiftRange]))
                else { continue }
                result.append(url)
            }
        }
        return result
    }

    /// Extracts absolute URIs with any scheme. The request validator uses this
    /// in addition to HTTP(S) URLs so DSNs such as `postgres://user:pass@host`
    /// cannot hide in an otherwise innocuous configuration string.
    nonisolated static func absoluteURLs(in text: String) -> [URL] {
        let pattern = #"(?i)(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"'`]+"#
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(location: 0, length: (text as NSString).length)
        return expression.matches(in: text, range: range).compactMap { match in
            guard let swiftRange = Range(match.range, in: text) else { return nil }
            return URL(string: String(text[swiftRange]))
        }
    }

    /// Relative and query-only references are included separately because
    /// `URL(string:)` has no host for them, but a signed query is just as
    /// sensitive when embedded in a script or configuration value.
    nonisolated static func relativeURLReferences(in text: String) -> [URL] {
        let patterns = [
            // Query separators may themselves be percent-encoded. Match the
            // whole relative reference and let URLComponents/query inspection
            // decide whether its decoded names or values are sensitive.
            #"(?i)(?<![A-Za-z0-9:/])/[^\s<>"'`]+\?[^\s<>"'`]*"#,
            #"(?i)(?<![A-Za-z0-9])\?[^\s<>"'`]*"#,
        ]
        var result: [URL] = []
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            for match in expression.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range, in: text),
                      let url = URL(string: String(text[swiftRange]))
                else { continue }
                result.append(url)
            }
        }
        return result
    }

    /// Removes credentials, fragments, and query values from every absolute URL
    /// in a remote string. This also covers URLs embedded in Markdown or HTML,
    /// where the containing JSON field name cannot be trusted.
    nonisolated static func redactURLQueries(in text: String) -> String {
        guard !Task.isCancelled else { return "" }
        let direct = redactingURLQueries(in: text)
        // Decoding is a detection probe only. Benign encoded text such as
        // `100%25 off` must reach the model byte-for-byte, so the canonical
        // form is adopted solely when it actually removes a reference from it.
        let canonical = canonicalizeRemoteText(text)
        if canonical != text {
            let decoded = redactingURLQueries(in: canonical)
            if decoded != canonical { return decoded }
        }
        return direct
    }

    /// One rewriting pass over a single concrete form of the text. This
    /// deliberately carries no cancellation handling: request validation reuses
    /// these patterns and must never observe a cancellation-emptied string.
    private nonisolated static func redactingURLQueries(in text: String) -> String {
        let patterns = [
            #"(?i)(?<![A-Za-z0-9+.-])[A-Za-z][A-Za-z0-9+.-]*://[^\s<>"'`]+"#,
            #"(?i)(?<![A-Za-z0-9:])//[^\s<>"'`]+"#,
            // Query separators may themselves be percent-encoded. Match the
            // whole relative reference and let URLComponents/query inspection
            // decide whether its decoded names or values are sensitive.
            #"(?i)(?<![A-Za-z0-9:/])/[^\s<>"'`]+\?[^\s<>"'`]*"#,
            #"(?i)(?<![A-Za-z0-9])\?[^\s<>"'`]*"#,
        ]
        var output = text
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = expression.matches(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else { continue }
                let raw = String(output[range])
                guard let url = URL(string: raw) else {
                    output.replaceSubrange(range, with: "[omitted: URL]")
                    continue
                }
                var components = URLComponents(url: url, resolvingAgainstBaseURL: false) ?? URLComponents()
                let hadQuery = components.query != nil
                components.user = nil
                components.password = nil
                components.query = nil
                components.fragment = nil
                let safe: String
                if let rendered = components.string {
                    safe = rendered + (hadQuery ? "…[query removed]" : "")
                } else {
                    safe = "[omitted: URL]"
                }
                if safe != raw {
                    output.replaceSubrange(range, with: safe)
                }
            }
        }
        return output
    }

    /// Removes credential-shaped text even when a remote service returns it in
    /// a plain string rather than under a JSON field name. This is deliberately
    /// applied at the final output boundary, not only while parsing JSON: an
    /// HTML/text response must not be able to smuggle a bearer header into the
    /// next model turn.
    nonisolated static func redactSensitiveText(_ text: String) -> String {
        guard !Task.isCancelled else { return "" }
        let direct = redactingSensitiveText(text)
        // As above: the decoded form is a detection probe. It replaces the
        // literal text only when redaction actually fires, so a benign
        // percent/entity escape is preserved rather than silently decoded.
        let canonical = canonicalizeRemoteText(direct)
        if canonical != direct {
            let decoded = redactingSensitiveText(canonical)
            if decoded != canonical { return decoded }
        }
        return direct
    }

    /// Cancellation-independent credential-shape probe for request validation.
    /// `redactSensitiveText` fails closed (returns `""`) when the current task is
    /// cancelled, so comparing its result against the input would reject every
    /// argument once the user pressed Stop. This predicate reads the same
    /// patterns without inheriting that behaviour.
    nonisolated static func containsSensitiveRemoteText(_ text: String) -> Bool {
        if redactingSensitiveText(text) != text { return true }
        // The decoded form is a detection probe on this side, not an output
        // format. An argument such as `password%3DSECRET` carries no literal
        // `=` and would otherwise pass an undecoded check.
        let canonical = canonicalizeRemoteText(text)
        return canonical != text && redactingSensitiveText(canonical) != canonical
    }

    /// One redaction pass over a single concrete form of the text. Like
    /// `redactingURLQueries`, this must stay free of cancellation handling so
    /// `containsSensitiveRemoteText` remains a stable predicate.
    private nonisolated static func redactingSensitiveText(_ text: String) -> String {
        let patterns: [(String, String)] = [
            (
                #"(?im)^[ \t]*(?:authorization|proxy-authorization|cookie|set-cookie|x-api-key|api-key|x-auth-token|authentication)[ \t]*:[ \t]*[^\r\n]*"#,
                "[omitted: sensitive header]"
            ),
            (
                #"(?i)\b(?:authorization|proxy-authorization|x-api-key|api-key|x-auth-token|authentication)[ \t]*[:=][ \t]*[^\s,;}\]]+"#,
                "[omitted: sensitive header]"
            ),
            (
                #"(?i)\b(?:bearer|basic)[ \t]+[A-Za-z0-9._~+/=-]{8,}"#,
                "[omitted: authorization value]"
            ),
            (
                #"(?i)\b(?:sk_(?:live|test)_[A-Za-z0-9_-]{8,}|sk-[A-Za-z0-9_-]{16,}|sk-ant-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9_]{20,}|glpat-[A-Za-z0-9_-]{16,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{20,}|xai-[0-9A-Za-z_-]{16,}|npm_[0-9A-Za-z]{20,}|dop_v1_[0-9A-Za-z]{16,}|hf_[0-9A-Za-z]{20,})\b"#,
                "[omitted: credential-shaped value]"
            ),
            (
                #"(?i)\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\b"#,
                "[omitted: bearer token]"
            ),
            (
                #"(?i)\b(?:access[_ -]?token|refresh[_ -]?token|api[_ -]?key|client[_ -]?secret|password|passwd|passphrase|signature|signed[_ -]?url|csrf[_ -]?token|jwt|nonce)[ \t]*[:=][ \t]*["']?[^,\s}\]]+"#,
                "[omitted: credential field]"
            ),
            (
                #"(?i)\b(?:cookie|set-cookie)["']?[ \t]*[:=][ \t]*[^,\s}\]]+(?:[ \t]*;[ \t]*[^,\s}\]]+)*"#,
                "[omitted: cookie value]"
            ),
            (
                #"(?s)-----BEGIN [A-Z0-9 ]*PRIVATE KEY-----.*?-----END [A-Z0-9 ]*PRIVATE KEY-----"#,
                "[omitted: private key]"
            ),
            (
                // Accept mixed percent/entity delimiters as well as fully
                // encoded URLs. The whole reference is removed, so a decoded
                // credential cannot survive in a trailing path or query.
                #"(?i)[A-Za-z][A-Za-z0-9+.-]*(?:%3a|&#(?:0*58|x0*3a);|&colon;)(?:(?:%2f|&#(?:0*47|x0*2f);|&sol;)|/){2}[^\s<>"'`]+"#,
                "[omitted: encoded remote URL]"
            ),
            (
                #"(?i)\bdata:[^\s<>"'`]+"#,
                "[omitted: embedded data URI]"
            ),
            (
                #"(?i)(?<![A-Za-z0-9+/=])[A-Za-z0-9+/]{256,}={0,2}(?![A-Za-z0-9+/=])"#,
                "[omitted: binary/base64 payload]"
            ),
        ]

        func redacted(_ value: String) -> String {
            var output = value
            for (pattern, replacement) in patterns {
                guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
                let matches = expression.matches(
                    in: output,
                    range: NSRange(output.startIndex..., in: output)
                )
                for match in matches.reversed() {
                    guard let range = Range(match.range, in: output) else { continue }
                    output.replaceSubrange(range, with: replacement)
                }
            }
            return output
        }

        return redacted(text)
    }

    /// Keeps the explicit HTML operation useful without allowing active markup
    /// or inline event handlers to reach the model. The server normally returns
    /// preprocessed HTML, but this second boundary keeps that guarantee local.
    nonisolated static func sanitizeHTML(_ text: String) -> String {
        guard !Task.isCancelled else { return "" }
        var output = text
        let blockPatterns = [
            #"(?is)<!--.*?-->"#,
            #"(?is)<script\b[^>]*>.*?</script\s*>"#,
            #"(?is)<style\b[^>]*>.*?</style\s*>"#,
            #"(?is)<iframe\b[^>]*>.*?</iframe\s*>"#,
            #"(?is)<object\b[^>]*>.*?</object\s*>"#,
            #"(?is)<embed\b[^>]*>.*?</embed\s*>"#,
            #"(?is)<noscript\b[^>]*>.*?</noscript\s*>"#,
        ]
        for pattern in blockPatterns {
            guard let expression = try? NSRegularExpression(pattern: pattern) else { continue }
            let matches = expression.matches(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else { continue }
                output.replaceSubrange(range, with: "")
            }
        }

        let eventPattern = #"(?is)\s+on[a-z0-9_-]+\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#
        if let expression = try? NSRegularExpression(pattern: eventPattern) {
            let matches = expression.matches(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else { continue }
                output.replaceSubrange(range, with: "")
            }
        }

        let stylePattern = #"(?is)\s+style\s*=\s*(?:"[^"]*"|'[^']*'|[^\s>]+)"#
        if let expression = try? NSRegularExpression(pattern: stylePattern) {
            let matches = expression.matches(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else { continue }
                output.replaceSubrange(range, with: "")
            }
        }

        let javascriptURLPattern = #"(?is)\s+(?:href|src|xlink:href)\s*=\s*["']?\s*(?:javascript|data):[^"'\s>]*["']?"#
        if let expression = try? NSRegularExpression(pattern: javascriptURLPattern) {
            let matches = expression.matches(
                in: output,
                range: NSRange(output.startIndex..., in: output)
            )
            for match in matches.reversed() {
                guard let range = Range(match.range, in: output) else { continue }
                output.replaceSubrange(range, with: " href=\"#\"")
            }
        }
        return output
    }

    /// Bounds and redacts a remote object key before it is echoed into
    /// model-visible output. A key that redaction had to touch at all is
    /// discarded rather than echoed, because the leftovers of a partial
    /// redaction can still be a secret (`Authorization: Bearer <jwt>` leaves the
    /// token behind). The positional fallback cannot collide with a real field.
    nonisolated static func safeRemoteFieldName(_ raw: String, fallback: String) -> String {
        let trimmed = String(raw.prefix(200))
        let safe = redactSensitiveText(trimmed).trimmingCharacters(in: .whitespacesAndNewlines)
        return safe.isEmpty || safe != trimmed ? fallback : safe
    }

    nonisolated static func sanitizeAndTruncate(_ text: String, limit: Int) -> String {
        let cap = max(1_000, limit)
        // Both redaction helpers also probe the percent/entity-decoded form, so
        // mixed forms such as `password%3DSECRET` cannot survive, while benign
        // encoded text keeps its original bytes. Redact before taking the prefix
        // so a credential split by truncation cannot remain as a partial secret.
        let sanitized = sanitizeHTML(redactSensitiveText(in: redactURLQueries(in: text)))
        guard sanitized.count > cap else { return sanitized }
        return String(sanitized.prefix(cap)) + "\n…[output capped at \(cap) characters]"
    }

    /// Removes base64 payloads, cookies/headers, live-session links, and
    /// high-volume diagnostics before a remote result is allowed into a model
    /// context. The omission is explicit so the model knows an artifact exists
    /// without spending its whole budget on image bytes.
    nonisolated static func compactJSONValue(_ value: Any, key: String? = nil, depth: Int = 0) -> Any {
        if Task.isCancelled { return "[omitted: cancelled]" }
        let omittedKeys: Set<String> = [
            "html", "cleaned_html", "fit_html", "raw_html", "mhtml", "screenshot", "pdf",
            "downloaded_files", "network_requests", "console_messages", "ssl_certificate",
            "request_headers", "response_headers", "http_headers", "extra_headers",
            "headers", "set_cookie", "cookie", "cookies",
            "session_id", "live_url", "live_url_info", "log_detail_url", "download_url",
            "signed_url", "signed", "signature", "csrf", "csrf_token", "jwt", "nonce",
            "screenshot_url", "image", "image_data", "image_base64",
            "binary_data", "bytes", "audio", "video", "authorization", "proxy_authorization",
            "api_key", "access_token", "refresh_token", "client_secret", "password", "secret",
            "credential", "credentials", "auth", "bearer",
        ]
        let normalizedKey = key.map { normalizedFieldName(canonicalizeRemoteText($0)) }
        if let key, let normalizedKey {
            let words = Set(normalizedKey.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))
            let sensitiveWords: Set<String> = [
                "password", "token", "secret", "credential", "credentials", "cookie",
                "authorization", "authentication", "auth", "bearer", "session", "key",
                "signature", "signed", "csrf", "jwt", "nonce",
            ]
            if omittedKeys.contains(normalizedKey) || !words.isDisjoint(with: sensitiveWords) {
                // The field name is server-controlled text and may itself carry a
                // credential, so the marker names the category, never the key.
                return "[omitted: sensitive field]"
            }
        }
        if depth >= 10 {
            return "[nested value omitted]"
        }

        if let dictionary = value as? [String: Any] {
            var output: [String: Any] = [:]
            for (index, name) in dictionary.keys.sorted().prefix(200).enumerated() {
                // Object keys are remote text, so they are bounded and redacted
                // before being echoed. The positional fallback keeps a key that
                // redacts away from colliding with a real field.
                let safeName = safeRemoteFieldName(name, fallback: "__omitted_field_\(index)__")
                output[safeName] = compactJSONValue(dictionary[name] ?? NSNull(), key: name, depth: depth + 1)
            }
            if dictionary.count > 200 {
                output["__app_omitted__"] = "\(dictionary.count - 200) additional fields omitted"
            }
            return output
        }
        if let array = value as? [Any] {
            return array.prefix(80).map { compactJSONValue($0, key: key, depth: depth + 1) }
        }
        if let string = value as? String {
            if string.lowercased().hasPrefix("data:") {
                return "[omitted: embedded data URI]"
            }
            let maxLength = normalizedKey == "markdown" || normalizedKey?.hasSuffix("_markdown") == true ? 8_000 : 3_000
            return sanitizeAndTruncate(sanitizeHTML(string), limit: maxLength)
        }
        return value
    }

    nonisolated static func compactJSONText(from data: Data, limit: Int) -> String? {
        guard !Task.isCancelled else { return nil }
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data),
              JSONSerialization.isValidJSONObject(object)
        else { return nil }
        let compacted = compactJSONValue(object)
        guard JSONSerialization.isValidJSONObject(compacted),
              let encoded = try? JSONSerialization.data(
                withJSONObject: compacted,
                options: [.prettyPrinted, .sortedKeys]
              )
        else { return nil }
        return truncate(String(decoding: encoded, as: UTF8.self), limit: limit)
    }

    /// Bounds a remote string. Unlike the other output helpers this one
    /// redacts first: it terminates `compactJSONText`, whose input is assembled
    /// from server-controlled object keys, and it must not be the one place in
    /// the output path that skips the credential grammar.
    nonisolated static func truncate(_ text: String, limit: Int) -> String {
        let cap = max(1_000, limit)
        let safe = redactSensitiveText(text)
        guard safe.count > cap else { return safe }
        return String(safe.prefix(cap)) + "\n…[output capped at \(cap) characters]"
    }

    private static func serverMessage(from data: Data) -> String {
        guard !data.isEmpty,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return String(data.prefix(300), encoding: .utf8) ?? ""
        }
        let message = object["msg"] ?? object["message"] ?? object["detail"]
        if let detail = message as? String { return String(detail.prefix(300)) }
        if let detail = message as? [String: Any],
           let nested = detail["msg"] as? String {
            return String(nested.prefix(300))
        }
        return ""
    }
}
