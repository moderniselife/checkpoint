import Foundation
#if os(macOS)
import AppKit
#else
import AuthenticationServices
import UIKit
#endif

/// Shows the OAuth consent page while the loopback server waits for the redirect.
/// The Mac uses the default browser (already signed in to Atlassian); iOS uses an
/// in-app web sheet so the app stays in the foreground and the listener keeps running.
@MainActor
final class AuthBrowser: NSObject {
    static let shared = AuthBrowser()

    #if os(iOS)
    private var session: ASWebAuthenticationSession?
    private var finishing = false
    #endif

    /// `onUserCancel` runs if the person closes the sheet before signing in.
    func present(_ url: URL, onUserCancel: @escaping @Sendable () -> Void) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        finishing = false
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
        #endif
    }
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
#endif
