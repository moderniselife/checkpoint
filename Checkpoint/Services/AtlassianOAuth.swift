import AppKit
import AuthenticationServices
import CryptoKit
import Foundation

/// OAuth 2.1 for the Atlassian Rovo MCP server: dynamic client registration,
/// PKCE authorization code flow via ASWebAuthenticationSession, and refresh.
actor AtlassianOAuth {
    static let shared = AtlassianOAuth()

    enum OAuthError: LocalizedError {
        case notSignedIn
        case cancelled
        case badResponse(String)

        var errorDescription: String? {
            switch self {
            case .notSignedIn: return "Not signed in to Atlassian. Sign in from Settings (⌘,)."
            case .cancelled: return "Atlassian sign-in was cancelled."
            case .badResponse(let s): return "Atlassian sign-in failed: \(s)"
            }
        }
    }

    nonisolated struct Tokens: Codable, Sendable {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    nonisolated static let redirectURI = "checkpoint://oauth/callback"
    nonisolated static let callbackScheme = "checkpoint"
    private static let base = URL(string: "https://mcp.atlassian.com/v1/")!
    private static let tokensAccount = "atlassian-oauth"
    private static let clientIDKey = "atlassianOAuthClientID"

    private var refreshTask: Task<Tokens, Error>?

    nonisolated var isSignedIn: Bool { Keychain.get(Self.tokensAccount) != nil }

    /// A valid access token, refreshing it first if it's about to expire.
    func accessToken() async throws -> String {
        guard var tokens = loadTokens() else { throw OAuthError.notSignedIn }
        if tokens.expiresAt.timeIntervalSinceNow < 60 {
            tokens = try await refresh(tokens)
        }
        return tokens.accessToken
    }

    /// Forces a refresh — used after the MCP server returns 401 mid-session.
    func forceRefresh() async throws {
        guard let tokens = loadTokens() else { throw OAuthError.notSignedIn }
        _ = try await refresh(tokens)
    }

    func signOut() {
        Keychain.set("", for: Self.tokensAccount)
    }

    // MARK: - Sign in

    func signIn() async throws {
        let clientID = try await clientID()
        let verifier = Self.randomURLSafe(32)
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URLEncoded
        let state = Self.randomURLSafe(16)

        var comps = URLComponents(url: Self.base.appending(path: "authorize"), resolvingAgainstBaseURL: false)!
        comps.queryItems = [
            .init(name: "response_type", value: "code"),
            .init(name: "client_id", value: clientID),
            .init(name: "redirect_uri", value: Self.redirectURI),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "state", value: state),
        ]

        let callback = try await WebAuth.run(url: comps.url!, scheme: Self.callbackScheme)
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
            "redirect_uri": Self.redirectURI,
            "client_id": clientID,
            "code_verifier": verifier,
        ], previousRefresh: nil)
        saveTokens(tokens)
    }

    // MARK: - Internals

    private func clientID() async throws -> String {
        if let id = UserDefaults.standard.string(forKey: Self.clientIDKey) { return id }
        var req = URLRequest(url: Self.base.appending(path: "register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: JSONValue = [
            "client_name": "Checkpoint",
            "redirect_uris": [.string(Self.redirectURI)],
            "grant_types": ["authorization_code", "refresh_token"],
            "response_types": ["code"],
            "token_endpoint_auth_method": "none",
        ]
        req.httpBody = try JSONCoding.encoder.encode(body)
        let (data, response) = try await URLSession.shared.data(for: req)
        let json = try? JSONCoding.decoder.decode(JSONValue.self, from: data)
        guard (response as? HTTPURLResponse)?.statusCode ?? 0 < 300, let id = json?["client_id"]?.stringValue else {
            throw OAuthError.badResponse("client registration failed: \(String(decoding: data, as: UTF8.self).prefix(200))")
        }
        UserDefaults.standard.set(id, forKey: Self.clientIDKey)
        return id
    }

    private func refresh(_ tokens: Tokens) async throws -> Tokens {
        // Coalesce concurrent refreshes (parallel tool calls) into one request.
        if let refreshTask { return try await refreshTask.value }
        guard let refreshToken = tokens.refreshToken else { throw OAuthError.notSignedIn }
        let clientID = try await clientID()
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
            throw OAuthError.notSignedIn
        }
    }

    private func tokenRequest(_ params: [String: String], previousRefresh: String?) async throws -> Tokens {
        var req = URLRequest(url: Self.base.appending(path: "token"))
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
        guard let raw = Keychain.get(Self.tokensAccount) else { return nil }
        return try? JSONDecoder().decode(Tokens.self, from: Data(raw.utf8))
    }

    private func saveTokens(_ tokens: Tokens) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        Keychain.set(String(decoding: data, as: UTF8.self), for: Self.tokensAccount)
    }

    private static func randomURLSafe(_ bytes: Int) -> String {
        var buf = [UInt8](repeating: 0, count: bytes)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes, &buf)
        return Data(buf).base64URLEncoded
    }
}

/// Runs ASWebAuthenticationSession on the main actor and returns the callback URL.
private final class WebAuth: NSObject, ASWebAuthenticationPresentationContextProviding {
    private static var current: WebAuth?
    private var session: ASWebAuthenticationSession?

    static func run(url: URL, scheme: String) async throws -> URL {
        let auth = WebAuth()
        current = auth
        defer { current = nil }
        return try await withCheckedThrowingContinuation { cont in
            let session = ASWebAuthenticationSession(url: url, callback: .customScheme(scheme)) { callback, error in
                if let callback {
                    cont.resume(returning: callback)
                } else if let error = error as? ASWebAuthenticationSessionError, error.code == .canceledLogin {
                    cont.resume(throwing: AtlassianOAuth.OAuthError.cancelled)
                } else {
                    cont.resume(throwing: error ?? AtlassianOAuth.OAuthError.cancelled)
                }
            }
            // Reuse the browser's existing Atlassian login.
            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = auth
            auth.session = session
            if !session.start() {
                cont.resume(throwing: AtlassianOAuth.OAuthError.badResponse("couldn't open the sign-in window"))
            }
        }
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
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
