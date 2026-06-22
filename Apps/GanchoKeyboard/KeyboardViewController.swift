import GanchoKit
import SwiftUI
import UIKit

/// The custom keyboard's principal class. Hosts the SwiftUI `KeyboardView`,
/// bridges text insertion to the `textDocumentProxy`, and drives the keyboard
/// height when the user toggles compact ↔ expanded.
final class KeyboardViewController: UIInputViewController {
    private var heightConstraint: NSLayoutConstraint?
    private static let compactHeight: CGFloat = 76
    private static let expandedHeight: CGFloat = 300

    override func viewDidLoad() {
        super.viewDidLoad()

        // Clip taps live inside scroll views; the default content-touch delay
        // makes a clipboard keyboard feel sluggish. Register taps immediately.
        UIScrollView.appearance().delaysContentTouches = false

        let model = KeyboardModel(
            hasFullAccess: hasFullAccess,
            onInsert: { [weak self] text in self?.textDocumentProxy.insertText(text) },
            onDelete: { [weak self] in self?.textDocumentProxy.deleteBackward() },
            onNextKeyboard: { [weak self] in self?.advanceToNextInputMode() })
        model.onModeChange = { [weak self] expanded in
            guard let self else { return }
            heightConstraint?.constant = expanded ? Self.expandedHeight : Self.compactHeight
            // Grow/shrink smoothly so the size change reads as intentional.
            UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseInOut) {
                self.view.layoutIfNeeded()
            }
        }

        let host = UIHostingController(rootView: KeyboardView(model: model))
        host.view.translatesAutoresizingMaskIntoConstraints = false
        host.view.backgroundColor = .clear
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)

        // Height constraint < required so it never fights the system's own
        // keyboard layout constraints (which would log conflicts). Open at the
        // expanded height to match the model's default expanded state.
        let height = view.heightAnchor.constraint(equalToConstant: Self.expandedHeight)
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height
    }
}
