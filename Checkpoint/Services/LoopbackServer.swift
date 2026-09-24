import Foundation
import Network

/// One-shot HTTP listener on 127.0.0.1 that catches the OAuth redirect.
/// Loopback redirects are pre-approved for the Atlassian MCP server in every org,
/// unlike custom URL schemes which need an admin to allowlist them.
nonisolated final class LoopbackServer: @unchecked Sendable {
    enum LoopbackError: LocalizedError {
        case portUnavailable
        case timedOut

        var errorDescription: String? {
            switch self {
            case .portUnavailable: return "Couldn't open a local port for the sign-in redirect."
            case .timedOut: return "Timed out waiting for Atlassian sign-in to finish."
            }
        }
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "checkpoint.loopback")
    private var continuation: CheckedContinuation<URL, Error>?
    private var boundPort: UInt16 = 0
    private var startContinuation: CheckedContinuation<UInt16, Error>?
    private let preferredPort: UInt16

    init(preferredPort: UInt16) {
        self.preferredPort = preferredPort
    }

    /// Binds 127.0.0.1 — the preferred port first (so the registered OAuth client
    /// can be reused), else any free port — and returns the redirect URI.
    func start() async throws -> String {
        let port: UInt16
        if let p = try? await bind(NWEndpoint.Port(rawValue: preferredPort)!) {
            port = p
        } else {
            port = try await bind(.any)
        }
        return "http://127.0.0.1:\(port)/callback"
    }

    private func bind(_ port: NWEndpoint.Port) async throws -> UInt16 {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: port)
        guard let listener = try? NWListener(using: params) else { throw LoopbackError.portUnavailable }
        self.listener = listener
        return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            // Handlers run serially on `queue`, so this state needs no extra locking.
            queue.async { self.startContinuation = cont }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                guard let self, let cont = self.startContinuation else { return }
                switch state {
                case .ready:
                    self.startContinuation = nil
                    self.boundPort = listener?.port?.rawValue ?? 0
                    cont.resume(returning: self.boundPort)
                case .failed, .waiting:
                    self.startContinuation = nil
                    listener?.cancel()
                    cont.resume(throwing: LoopbackError.portUnavailable)
                default: break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in self?.handle(conn) }
            listener.start(queue: queue)
        }
    }

    /// Waits for the browser to hit /callback and returns the full callback URL.
    func waitForCallback(timeout: Duration = .seconds(300)) async throws -> URL {
        try await withThrowingTaskGroup(of: URL.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { cont in
                    self.queue.async { self.continuation = cont }
                }
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LoopbackError.timedOut
            }
            defer { group.cancelAll(); stop() }
            return try await group.next()!
        }
    }

    func stop() {
        listener?.cancel()
        queue.async {
            self.continuation?.resume(throwing: CancellationError())
            self.continuation = nil
        }
    }

    private func handle(_ conn: NWConnection) {
        conn.start(queue: queue)
        conn.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            let request = data.map { String(decoding: $0, as: UTF8.self) } ?? ""
            // "GET /callback?code=…&state=… HTTP/1.1"
            let target = request.split(separator: " ").dropFirst().first.map(String.init) ?? ""
            let url = URL(string: "http://127.0.0.1:\(self.boundPort)\(target)")

            guard let url, url.path == "/callback" else {
                self.respond(conn, status: "404 Not Found", body: "Not found")
                return
            }
            let failed = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?.contains { $0.name == "error" } ?? false
            self.respond(conn, status: "200 OK", body: Self.page(success: !failed))
            self.continuation?.resume(returning: url)
            self.continuation = nil
        }
    }

    private func respond(_ conn: NWConnection, status: String, body: String) {
        let bytes = Data(body.utf8)
        let head = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(bytes.count)\r\nConnection: close\r\n\r\n"
        conn.send(content: Data(head.utf8) + bytes, completion: .contentProcessed { _ in conn.cancel() })
    }

    private static func page(success: Bool) -> String {
        let title = success ? "Signed in to Checkpoint" : "Sign-in didn't complete"
        let body = success ? "You can close this tab and head back to Checkpoint." : "Head back to Checkpoint and try again."
        return """
        <!doctype html><meta charset="utf-8"><title>\(title)</title>
        <style>body{font:16px -apple-system,system-ui;display:grid;place-items:center;height:100vh;margin:0;background:#f5f5f7;color:#1d1d1f}
        @media(prefers-color-scheme:dark){body{background:#1d1d1f;color:#f5f5f7}}div{text-align:center}h1{font-size:22px}</style>
        <div><h1>\(title)</h1><p>\(body)</p></div>
        <script>setTimeout(()=>window.close(),1500)</script>
        """
    }
}
