import SwiftUI
import UIKit

/// Tapping anywhere that isn't a text field closes the keyboard, like most iOS apps.
/// A window-level tap recognizer that never cancels the tap, so buttons, rows and
/// menus under the finger still work as usual.
struct KeyboardDismisser: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async { context.coordinator.install(in: view.window) }
        return view
    }

    func updateUIView(_ view: UIView, context: Context) {
        context.coordinator.install(in: view.window)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private var recognizer: UITapGestureRecognizer?

        func install(in window: UIWindow?) {
            guard let window, window !== self.window else { return }
            if let recognizer { recognizer.view?.removeGestureRecognizer(recognizer) }
            let tap = UITapGestureRecognizer(target: self, action: #selector(tapped))
            // Never hold back or swallow the touch: switches, sliders and buttons under the
            // finger must get it exactly as if this recognizer weren't there.
            tap.cancelsTouchesInView = false
            tap.delaysTouchesBegan = false
            tap.delaysTouchesEnded = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            self.window = window
            recognizer = tap
        }

        @objc private func tapped() {
            window?.endEditing(true)
        }

        /// Only in play while something is being edited, so it never touches ordinary taps.
        func gestureRecognizerShouldBegin(_ g: UIGestureRecognizer) -> Bool {
            window?.firstResponderIsTextInput ?? false
        }

        /// Taps on a text field (or inside one) keep the keyboard, so moving the caret still works.
        func gestureRecognizer(_ g: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let v = view {
                if v is UITextField || v is UITextView || v is UISearchBar { return false }
                view = v.superview
            }
            return true
        }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}

private extension UIView {
    /// Whether a text field or text view in this view's tree is being edited.
    var firstResponderIsTextInput: Bool {
        if isFirstResponder { return self is UITextField || self is UITextView || self is UISearchTextField }
        return subviews.contains { $0.firstResponderIsTextInput }
    }
}
