import SwiftUI
#if canImport(AppKit)
import AppKit
typealias PlatformImage = NSImage
#else
import UIKit
typealias PlatformImage = UIImage
#endif

/// The few things macOS and iOS do differently, behind one name.
enum Platform {
    static var isMac: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// How to refer to Settings in messages: the Mac has a shortcut, iOS a gear.
    nonisolated static var settingsName: String {
        #if os(macOS)
        "Settings (⌘,)"
        #else
        "Settings (the gear in the plan list)"
        #endif
    }

    static func open(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.open(url)
        #else
        UIApplication.shared.open(url)
        #endif
    }

    static func copy(_ string: String) {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(string, forType: .string)
        #else
        UIPasteboard.general.string = string
        #endif
    }

    /// Shows a saved file: Finder on the Mac, a preview-capable open on iOS.
    static func reveal(_ url: URL) {
        #if os(macOS)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        #else
        UIApplication.shared.open(url)
        #endif
    }
}

extension Image {
    init(platformImage: PlatformImage) {
        #if os(macOS)
        self.init(nsImage: platformImage)
        #else
        self.init(uiImage: platformImage)
        #endif
    }
}

/// Page margins. On the Mac, content starts below the floating ticket bar;
/// on iOS the bar isn't overlaid, so pages start near the top.
enum PageLayout {
    #if os(macOS)
    static let top: CGFloat = 92
    static let feedTop: CGFloat = 96
    static let side: CGFloat = 28
    #else
    static let top: CGFloat = 12
    static let feedTop: CGFloat = 16
    static let side: CGFloat = 16
    #endif
}

/// "Open Settings" for views shared by both apps: a window on the Mac, a sheet on iOS
/// (the iOS root view supplies the action).
struct ShowSettingsAction {
    var action: () -> Void = {}
    func callAsFunction() { action() }
}

extension EnvironmentValues {
    @Entry var showSettings = ShowSettingsAction()
}
