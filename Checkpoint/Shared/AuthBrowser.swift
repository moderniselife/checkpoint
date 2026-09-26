import Foundation
#if os(macOS)
import AppKit
#else
import AuthenticationServices
import SwiftUI
import UIKit
import WebKit
#endif

/// Shows the OAuth consent page while the loopback server waits for the redirect.
///
/// - Mac: the default browser, already signed in to Atlassian.
/// - iOS: an in-app sheet so the app stays in the foreground and the listener keeps
///   running. Atlassian uses Checkpoint's own web view: with the Jira app installed,
///   iOS hands atlassian.com links to it mid-flow and the redirect never comes back,
///   and universal links can't fire inside a web view. That sheet can switch to the
///   system browser sheet for sign-in providers that refuse embedded web views.
@MainActor
final class AuthBrowser: NSObject {
    static let shared = AuthBrowser()

    #if os(iOS)
    private var session: ASWebAuthenticationSession?
    private var webSheet: UIViewController?
    private var finishing = false
    #endif

    /// `inApp` asks for the embedded web view on iOS (ignored on the Mac).
    /// `onUserCancel` runs if the person closes the sheet before signing in.
    func present(_ url: URL, inApp: Bool = false, onUserCancel: @escaping @Sendable () -> Void) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        finishing = false
        if inApp {
            presentWebSheet(url, onUserCancel: onUserCancel)
        } else {
            presentSystemSheet(url, onUserCancel: onUserCancel)
        }
        #endif
    }

    /// The redirect arrived: bring Checkpoint back (Mac) or close the sheet (iOS).
    func finish() {
        #if os(macOS)
        NSApp.activate()
        #else
        finishing = true
        session?.cancel()
        session = nil
        webSheet?.dismiss(animated: true)
        webSheet = nil
        #endif
    }

    #if os(iOS)
    private func presentSystemSheet(_ url: URL, onUserCancel: @escaping @Sendable () -> Void) {
        // The callback scheme never fires: the redirect goes to the loopback server,
        // and `finish()` closes the sheet once it arrives.
        let s = ASWebAuthenticationSession(url: url, callback: .customScheme("checkpoint-auth")) { [weak self] _, _ in
            Task { @MainActor in
                guard let self else { return }
                if !self.finishing { onUserCancel() }
                self.session = nil
            }
        }
        s.presentationContextProvider = self
        s.prefersEphemeralWebBrowserSession = false
        session = s
        s.start()
    }

    private func presentWebSheet(_ url: URL, onUserCancel: @escaping @Sendable () -> Void) {
        let view = InAppSignInView(url: url) { [weak self] in
            // Cancel
            self?.webSheet?.dismiss(animated: true)
            self?.webSheet = nil
            onUserCancel()
        } useSafari: { [weak self] in
            guard let self else { return }
            self.webSheet?.dismiss(animated: true) {
                Task { @MainActor in self.presentSystemSheet(url, onUserCancel: onUserCancel) }
            }
            self.webSheet = nil
        }
        let host = UIHostingController(rootView: view)
        host.modalPresentationStyle = .pageSheet
        host.isModalInPresentation = true
        webSheet = host
        Self.topController()?.present(host, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.flatMap(\.windows).first { $0.isKeyWindow }?.rootViewController
        while let next = top?.presentedViewController { top = next }
        return top
    }
    #endif
}

#if os(iOS)
extension AuthBrowser: ASWebAuthenticationPresentationContextProviding {
    nonisolated func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        MainActor.assumeIsolated {
            let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            return scenes.flatMap(\.windows).first { $0.isKeyWindow } ?? ASPresentationAnchor()
        }
    }
}

/// Sign-in inside Checkpoint: a web view with Cancel and a Safari fallback.
private struct InAppSignInView: View {
    let url: URL
    let cancel: () -> Void
    let useSafari: () -> Void
    @State private var loading = true

    var body: some View {
        NavigationStack {
            SignInWebView(url: url, loading: $loading)
                .ignoresSafeArea(edges: .bottom)
                .overlay { if loading { ProgressView() } }
                .navigationTitle(url.host() ?? "Sign in")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel", action: cancel) }
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            Button("Open in Safari Instead", systemImage: "safari", action: useSafari)
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
                .safeAreaInset(edge: .bottom) {
                    Text("Signing in with Google or another provider that won't load here? Use ⋯ → Open in Safari Instead.")
                        .font(.caption).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20).padding(.vertical, 10)
                        .frame(maxWidth: .infinity)
                        .background(.bar)
                }
        }
    }
}

private struct SignInWebView: UIViewRepresentable {
    let url: URL
    @Binding var loading: Bool

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        let web = WKWebView(frame: .zero, configuration: config)
        web.navigationDelegate = context.coordinator
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(loading: $loading) }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var loading: Binding<Bool>
        init(loading: Binding<Bool>) { self.loading = loading }

        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { loading.wrappedValue = true }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) { loading.wrappedValue = false }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) { loading.wrappedValue = false }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            loading.wrappedValue = false
        }
    }
}
#endif
