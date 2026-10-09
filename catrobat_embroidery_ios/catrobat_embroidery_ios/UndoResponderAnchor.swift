import SwiftUI
import UIKit

/// An invisible first responder that hands the editor's own `UndoManager` to the responder chain
/// (US-411), so shake, ⌘Z and the edit menu reach `UndoManagerBridge`.
///
/// **Without it the system affordances do nothing in the editor**: shake-to-undo asks the first
/// responder for its manager, and a script list has no first responder (probe E2). With it, the
/// system offers the bridge's undo *and* redo (O2, O3).
///
/// **It never takes first responder from a text field.** It claims only when it enters a window
/// and when the keyboard has gone — never on a view update, which on iPad would end typing in the
/// stage's design-name field beside the list. While a parameter field is focused the field is
/// first responder, so shake undoes the *typing*, on the window's manager, and the program
/// history is not touched (O5). UIKit hands first responder back when the sheet closes (O6).
///
/// Lives in the view, so ADR-023's container swap destroys it and the new container's anchor
/// claims again. The manager does not live here: it belongs to `EditorViewModel`, which outlives
/// the swap.
struct UndoResponderAnchor: UIViewRepresentable {
    let manager: UndoManager?

    func makeUIView(context _: Context) -> AnchorView {
        AnchorView()
    }

    func updateUIView(_ view: AnchorView, context _: Context) {
        view.manager = manager
    }

    final class AnchorView: UIView {
        var manager: UndoManager?

        private var keyboardObserver: NSObjectProtocol?

        override init(frame: CGRect) {
            super.init(frame: frame)
            isAccessibilityElement = false
            accessibilityElementsHidden = true
            isUserInteractionEnabled = false
            keyboardObserver = NotificationCenter.default.addObserver(
                forName: UIResponder.keyboardDidHideNotification, object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.claim() }
            }
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is not supported")
        }

        isolated deinit {
            if let keyboardObserver {
                NotificationCenter.default.removeObserver(keyboardObserver)
            }
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
            guard window != nil, !isFirstResponder else { return }
            becomeFirstResponder()
        }
    }
}
