import AppKit
import SwiftUI

/// Composes a `BrowserChromeView` (top) and a `BrowserPaneView` (bottom) into
/// the single `NSView` that gets wrapped inside a `PaneLeaf.browser` case.
///
/// Layout: 30pt chrome strip on top, web view fills the remainder. No spacing.
class BrowserPaneContainer: NSView, Codable, Identifiable {
    typealias ID = UUID

    var id: UUID { browserPane.id }
    let browserPane: BrowserPaneView

    private let chromeModel = BrowserChromeModel()
    private let chromeHost: NSHostingView<BrowserChromeView>

    // MARK: - Proxied properties

    var url: URL? { browserPane.url }
    var title: String { browserPane.title }
    var canGoBack: Bool { browserPane.canGoBack }
    var canGoForward: Bool { browserPane.canGoForward }
    var isLoading: Bool { browserPane.isLoading }

    // MARK: - Init

    convenience init(url: URL) {
        self.init(url: url, id: UUID())
    }

    init(url: URL, id: UUID) {
        let pane = BrowserPaneView(url: url, id: id)
        self.browserPane = pane
        self.chromeHost = NSHostingView(rootView: BrowserChromeView(model: chromeModel, pane: pane))
        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — use init(from:) for Codable")
    }

    private func setup() {
        chromeHost.translatesAutoresizingMaskIntoConstraints = false
        browserPane.translatesAutoresizingMaskIntoConstraints = false
        addSubview(chromeHost)
        addSubview(browserPane)

        NSLayoutConstraint.activate([
            chromeHost.topAnchor.constraint(equalTo: topAnchor),
            chromeHost.leadingAnchor.constraint(equalTo: leadingAnchor),
            chromeHost.trailingAnchor.constraint(equalTo: trailingAnchor),
            chromeHost.heightAnchor.constraint(equalToConstant: 30),

            browserPane.topAnchor.constraint(equalTo: chromeHost.bottomAnchor),
            browserPane.leadingAnchor.constraint(equalTo: leadingAnchor),
            browserPane.trailingAnchor.constraint(equalTo: trailingAnchor),
            browserPane.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        wireChromeModel()
    }

    private func wireChromeModel() {
        chromeModel.onBack = { [weak self] in self?.browserPane.goBack() }
        chromeModel.onForward = { [weak self] in self?.browserPane.goForward() }
        chromeModel.onReload = { [weak self] in self?.browserPane.reload() }
        chromeModel.onSubmit = { [weak self] url in self?.browserPane.load(url: url) }
        chromeModel.onClose = { [weak self] in
            guard let self,
                  let controller = self.window?.windowController as? BaseTerminalController,
                  let node = controller.surfaceTree.root?.find(id: self.id)
            else { return }
            // Resolve the target from `self` rather than `focusedLeaf`: a
            // SwiftUI button tap inside the chrome's hosting view does not
            // make the container first responder, so focus tracking never
            // runs and `focusedLeaf` still points at the previously focused
            // terminal.
            controller.closeSurface(node, withConfirmation: false)
        }
    }

    /// Focus the omnibar. Wired to Cmd+L by the menu in a later task.
    func focusOmnibar() {
        chromeModel.addressBarFocused = true
        window?.makeFirstResponder(chromeHost)
    }

    /// Resolve the `PaneLeaf` for this container via the split tree and
    /// notify the controller that focus entered it.  Shared by all browser
    /// views that override `becomeFirstResponder`.
    func notifyControllerOfFocus() {
        guard let controller = window?.windowController as? BaseTerminalController,
              case .leaf(let leaf) = controller.surfaceTree.root?.find(id: self.id)
        else { return }
        controller.noteFirstResponderEnteredLeaf(leaf)
    }

    // MARK: - Responder chain

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        notifyControllerOfFocus()
        // If the omnibar is focused, leave focus with the chrome; otherwise
        // forward to the web view so typing goes into the page.
        if chromeModel.addressBarFocused {
            return window?.makeFirstResponder(chromeHost) ?? false
        }
        return window?.makeFirstResponder(browserPane) ?? false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }

        // When the web view has focus (omnibar inactive), standard editing
        // shortcuts must bypass the chrome's NSHostingView, which silently
        // consumes Cmd+C/V/X/A/Z even when its SwiftUI TextField is not
        // focused. Forward directly to the browser pane instead.
        if !chromeModel.addressBarFocused {
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            if flags == .command || flags == [.command, .shift] {
                if let chars = event.charactersIgnoringModifiers?.lowercased(),
                   ["c", "v", "x", "a", "z"].contains(chars) {
                    return browserPane.performKeyEquivalent(with: event)
                }
            }
        }

        // Let Ghostty's key bindings claim the event before the web view.
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - Codable

    enum CodingKeys: String, CodingKey {
        case id
        case url
    }

    required convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let idString = try container.decode(String.self, forKey: .id)
        let id = UUID(uuidString: idString) ?? UUID()
        let urlString = try container.decode(String.self, forKey: .url)
        let url = URL(string: urlString) ?? URL(string: "about:blank")!
        self.init(url: url, id: id)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id.uuidString, forKey: .id)
        let persistedURL = browserPane.url?.absoluteString ?? "about:blank"
        try container.encode(persistedURL, forKey: .url)
    }
}
