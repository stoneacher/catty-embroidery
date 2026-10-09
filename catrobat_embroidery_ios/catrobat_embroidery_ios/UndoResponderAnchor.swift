import SwiftUI
import UIKit

/// An invisible first responder that hands the editor's own `UndoManager` to the responder chain
/// (US-411), so shake, ⌘Z and the edit menu reach `UndoManagerBridge`.
///
/// **Without it the system affordances do nothing in the editor**: shake-to-undo asks the first
/// responder for its manager, and a script list has no first responder (probe E2). With it, the
/// system offers the bridge's undo *and* redo (O2, O3).
///
/// **It never takes first responder from a text field.** It tries to claim when it enters a
/// window, when a window becomes key and when the keyboard has gone, and succeeds only in the key
/// window with no text input first responder (`shouldClaim`). Never on a view update, which on
/// iPad would end typing in the stage's design-name field beside the list. While a parameter field is focused the field
/// is
/// first responder, so shake undoes the *typing*, on the window's manager, and the program
/// history is not touched (O5). UIKit hands first responder back when the sheet closes (O6).
///
/// Lives in the view, so ADR-023's container swap destroys it and the new container's anchor
/// claims again. The manager does not live here: it belongs to `EditorViewModel`, which outlives
/// the swap.
struct UndoResponderAnchor: UIViewRepresentable {
    let manager: UndoManager?

    /// Whether the anchor may take first responder: only in the key window, and never from a
    /// text input. The keyboard notification is app-wide, so another window's keyboard hiding
    /// reaches every anchor, and on iPad a background window keeps its own first responder — a
    /// claim there would end typing in that window's design-name field (`swift-code-reviewer`).
    nonisolated static func shouldClaim(isKeyWindow: Bool, textInputActive: Bool) -> Bool {
        isKeyWindow && !textInputActive
    }

    func makeUIView(context _: Context) -> AnchorView {
        AnchorView()
    }

    func updateUIView(_ view: AnchorView, context _: Context) {
        view.manager = manager
    }

    final class AnchorView: UIView {
        var manager: UndoManager?

        private var observers: [NSObjectProtocol] = []

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            isUserInteractionEnabled = false
            // The keyboard going, and this window becoming key — at launch it may not be key yet
            // when the anchor arrives, and `claim()` declines in a window that is not.
            for name in [UIResponder.keyboardDidHideNotification, UIWindow.didBecomeKeyNotification] {
                observers.append(NotificationCenter.default.addObserver(
                    forName: name, object: nil, queue: .main
                ) { [weak self] _ in
                    MainActor.assumeIsolated { self?.claim() }
                })
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        isolated deinit {
            observers.forEach(NotificationCenter.default.removeObserver)
        }

        override var canBecomeFirstResponder: Bool {
            manager != nil
        }

        override var undoManager: UndoManager? {
            manager ?? super.undoManager
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Next turn: SwiftUI has not finished installing the hierarchy when this is called.
            Task { @MainActor [weak self] in self?.claim() }
        }

        private func claim() {
            guard let window, !isFirstResponder else { return }
            let textInputActive = FirstResponder.current() is UITextInput
            guard UndoResponderAnchor.shouldClaim(isKeyWindow: window.isKeyWindow, textInputActive: textInputActive)
            else { return }
            becomeFirstResponder()
        }
    }
}

/// The key window's current first responder, found the documented way: an action sent to a `nil`
/// target goes to the first responder, which records itself.
@MainActor
private enum FirstResponder {
    private weak static var found: UIResponder?

    static func current() -> UIResponder? {
        found = nil
        UIApplication.shared.sendAction(#selector(UIResponder.recordAsFirstResponder), to: nil, from: nil, for: nil)
        return found
    }

    fileprivate static func record(_ responder: UIResponder) {
        found = responder
    }
}

private extension UIResponder {
    @objc func recordAsFirstResponder() {
        FirstResponder.record(self)
    }
}
