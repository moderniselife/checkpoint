import AppKit
import CryptoKit
import Foundation

/// OAuth 2.1 for a remote MCP server (Atlassian Rovo, Linear): dynamic client
/// registration, PKCE authorization code flow with a loopback redirect, and refresh.
actor MCPOAuth {
    static let atlassian = MCPOAuth(name: "Atlassian", base: URL(string: "https://mcp.atlassian.com/v1/")!,
                                   storageKey: "atlassian", scope: nil)
    /// `read` scope: Linear guarantees the token can't reach write APIs.
    static let linear = MCPOAuth(name: "Linear", base: URL(string: "https://mcp.linear.app/")!,
                                storageKey: "linear", scope: "read")

    nonisolated let name: String
    private let base: URL
    private let scope: String?
    private nonisolated let tokensAccount: String
    private let clientIDsKey: String
    private let activeClientKey: String

    init(name: String, base: URL, storageKey: String, scope: String?) {
        self.name = name
        self.base = base
        self.scope = scope
        // Atlassian keeps its original storage keys so existing sign-ins survive.
        tokensAccount = "\(storageKey)-oauth"
        clientIDsKey = "\(storageKey)OAuthClientIDs"
        activeClientKey = "\(storageKey)OAuthActiveClient"
    }

    enum OAuthError: LocalizedError {
        case notSignedIn(String)
        case cancelled
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn(let name): return "Not signed in to \(name). Sign in from Settings (⌘,)."
            case .cancelled: return "Sign-in was cancelled."
            case .badResponse(let s): return "Sign-in failed: \(s)"
            }
        }
    }

    nonisolated struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    /// Preferred loopback port; a different free port is used (and a new client registered) if it's taken.
    private static let preferredPort: UInt16 = 33418

    private var refreshTask: Task<Tokens, Error>?

    nonisolated var isSignedIn: Bool { Keychain.get(tokensAccount) != nil }

    /// A valid access token, refreshing it first if it's about to expire.
    func accessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw OAuthError.notSignedIn(name) }
        if tokens.expiresAt.timeIntervalSinceNow < 60 {
            tokens = try await refresh(tokens)
        }
        return tokens.accessToken
    }

    /// Forces a refresh — used after the MCP server returns 401 mid-session.
    func forceRefresh() async throws {
        guard let tokens = loadTokens() else { throw OAuthError.notSignedIn(name) }
        _ = try await refresh(tokens)
    }

    func signOut() {
        Keychain.set("", for: tokensAccount)
    }

    // MARK: - Sign in

    func signIn() async throws {
        let server = LoopbackServer(preferredPort: Self.preferredPort)
        let redirectURI = try await server.start()
        defer { server.stop() }
        let clientID = try await clientID(for: redirectURI)
        let verifier = Self.randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomURLSafe(16)

        var comps = URLComponents(url: base.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]
        if let scope { comps.queryItems?.append(.init(name: "scope", value: scope)) }

        // Default browser: already signed in to Atlassian, and loopback needs no admin allowlisting.
        await MainActor.run { _ = NSWorkspace.shared.open(comps.url!) }
        let callback = try await server.waitForCallback()
        await MainActor.run { NSApp.activate() }
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        if let err = items.first(where: { $0.name == "error" })?.value {
            let desc = items.first(where: { $0.name == "error_description" })?.value ?? err
            throw OAuthError.badResponse(desc)
        }
        guard items.first(where: { $0.name == "state" })?.value == state else {
            throw OAuthError.badResponse("state mismatch")
        }
        guard let code = items.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.badResponse("no authorization code returned")
        }

        let tokens = try await tokenRequest([
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefresh: nil)
        saveTokens(tokens)
        UserDefaults.standard.set(clientID, forKey: activeClientKey)
    }

    // MARK: - Internals


    private func clientID(for redirectURI: String) async throws -> String {
        var ids = UserDefaults.standard.dictionary(forKey: clientIDsKey) as? [String: String] ?? [:]
        if let id = ids[redirectURI] { return id }
        var req = URLRequest(url: base.appending(path: "register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: JSONValue = [
            "client_name": "Checkpoint",
            "redirect_uris": [.string(redirectURI)],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ]
        if let scope, case .object(var o) = body { o["scope"] = .string(scope); body = .object(o) }
        req.httpBody = try JSONCoding.encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = try? JSONCoding.decoder.decode(JSONValue.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300, let id = json?["client_id"]?.stringValue else {
            throw OAuthError.badResponse("client registration failed: \(String(decoding: data, as: UTF8.self).prefix(200))")
        }
        ids[redirectURI] = id
        UserDefaults.standard.set(ids, forKey: clientIDsKey)
        return id
    }

    private func refresh(_ tokens: Tokens) async throws -> Tokens {
        // Coalesce concurrent refreshes (parallel tool calls) into one request.
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens.refreshToken,
              let clientID = UserDefaults.standard.string(forKey: activeClientKey) else { throw OAuthError.notSignedIn(name) }
        let task = Task {
            try await self.tokenRequest([
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": clientID,
            ], previousRefresh: refreshToken)
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let new = try await task.value
            saveTokens(new)
            return new
        } catch {
            // A dead refresh token means the user has to sign in again.
            signOut()
            throw OAuthError.notSignedIn(name)
        }
    }

    private func tokenRequest(_ params: [String: String], previousRefresh: String?) async throws -> Tokens {
        var req = URLRequest(url: base.appending(path: "token"))
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        var form = URLComponents()
        form.queryItems = params.map { URLQueryItem(name: $0.key, value: $0.value) }
        req.httpBody = Data((form.percentEncodedQuery ?? "")
            .replacingOccurrences(of: "+", with: "%2B").utf8)

        let (data, response) = try await URLSession.shared.data(for: req)
        let json = try? JSONCoding.decoder.decode(JSONValue.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let access = json?["access_token"]?.stringValue else {
            let msg = json?["error_description"]?.stringValue ?? json?["error"]?.stringValue
                ?? String(decoding: data, as: UTF8.self).prefix(200).description
            throw OAuthError.badResponse(msg)
        }
        var expiresIn = 3600.0
        if case .number(let n) = json?["expires_in"] ?? .null { expiresIn = n }
        return Tokens(
            accessToken: access,
            refreshToken: json?["refresh_token"]?.stringValue ?? previousRefresh,
            expiresAt: Date().addingTimeInterval(expiresIn)
        )
    }

    private func loadTokens() -> Tokens? {
        guard let raw = Keychain.get(tokensAccount) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: Data(raw.utf8))
    }

    private func saveTokens(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        Keychain.set(String(decoding: data, as: UTF8.self), for: tokensAccount)
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buf)
        return Data(buf).base64URLEncoded
    }
}

nonisolated extension Data {
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
