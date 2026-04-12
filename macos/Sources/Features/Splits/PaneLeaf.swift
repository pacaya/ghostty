import AppKit

/// A leaf node in the split tree that wraps either a Ghostty terminal surface
/// or a browser pane container. Hosts its wrapped child as a single subview
/// pinned to bounds; responder-chain methods forward to the wrapped child.
final class PaneLeaf: NSView, Codable, Identifiable {
    typealias ID = UUID

    /// Stable identifier for this leaf. Matches the wrapped view's id so
    /// existing lookups keyed on `SurfaceView.id` / `BrowserPaneContainer.id`
    /// continue to work when talking about a leaf.
    let id: UUID

    /// The concrete pane kind held by this leaf.
    enum Kind {
        case terminal(Ghostty.SurfaceView)
        case browser(BrowserPaneContainer)
    }

    let kind: Kind

    // MARK: - Kind accessors

    /// Non-nil when this leaf hosts a terminal surface.
    var terminal: Ghostty.SurfaceView? {
        if case .terminal(let v) = kind { return v } else { return nil }
    }

    /// Non-nil when this leaf hosts a browser container.
    var browser: BrowserPaneContainer? {
        if case .browser(let v) = kind { return v } else { return nil }
    }

    var isTerminal: Bool { terminal != nil }
    var isBrowser: Bool { browser != nil }

    var title: String {
        switch kind {
        case .terminal(let v): return v.title
        case .browser(let v): return v.title
        }
    }

    /// The wrapped child as a plain `NSView` for layout / responder work.
    private var child: NSView {
        switch kind {
        case .terminal(let v): return v
        case .browser(let v): return v
        }
    }

    // MARK: - Init

    init(terminal: Ghostty.SurfaceView) {
        self.id = terminal.id
        self.kind = .terminal(terminal)
        super.init(frame: terminal.frame)
        attachChild(terminal)
    }

    init(browser: BrowserPaneContainer) {
        self.id = browser.id
        self.kind = .browser(browser)
        super.init(frame: browser.frame)
        attachChild(browser)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported — use init(from:) for Codable")
    }

    private func attachChild(_ view: NSView) {
        view.translatesAutoresizingMaskIntoConstraints = true
        view.autoresizingMask = [.width, .height]
        view.frame = bounds
        addSubview(view)
    }

    // MARK: - Responder chain forwarding

    override var acceptsFirstResponder: Bool {
        child.acceptsFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        if let controller = window?.windowController as? BaseTerminalController {
            controller.focusedLeaf = self
        }
        return window?.makeFirstResponder(child) ?? false
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        // Let Ghostty's multiplexer bindings claim the event before the child.
        if super.performKeyEquivalent(with: event) { return true }
        return child.performKeyEquivalent(with: event)
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case tag
        case payload
    }

    private enum Tag: String, Codable {
        case terminal
        case browser
    }

    convenience init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Legacy path: v7 archives encoded a bare SurfaceView with no `tag`
        // or `payload` keys. Decode the top level as a SurfaceView directly.
        guard let tag = try container.decodeIfPresent(Tag.self, forKey: .tag) else {
            let surface = try Ghostty.SurfaceView(from: decoder)
            self.init(terminal: surface)
            return
        }
        switch tag {
        case .terminal:
            let surface = try container.decode(Ghostty.SurfaceView.self, forKey: .payload)
            self.init(terminal: surface)
        case .browser:
            let browser = try container.decode(BrowserPaneContainer.self, forKey: .payload)
            self.init(browser: browser)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch kind {
        case .terminal(let v):
            try container.encode(Tag.terminal, forKey: .tag)
            try container.encode(v, forKey: .payload)
        case .browser(let v):
            try container.encode(Tag.browser, forKey: .tag)
            try container.encode(v, forKey: .payload)
        }
    }
}

// MARK: - Equatable

extension PaneLeaf {
    static func == (lhs: PaneLeaf, rhs: PaneLeaf) -> Bool {
        lhs === rhs
    }
}

extension NSView {
    /// Walk up the view hierarchy to find the enclosing `PaneLeaf`, if any.
    /// Used to locate the leaf a first-responder change landed in when
    /// AppKit bypassed `PaneLeaf.becomeFirstResponder` (e.g. a click that
    /// targeted a deeply nested view like a WKWebView directly).
    func enclosingPaneLeaf() -> PaneLeaf? {
        var v: NSView? = self
        while let cur = v {
            if let leaf = cur as? PaneLeaf { return leaf }
            v = cur.superview
        }
        return nil
    }

    /// Walk up the view hierarchy to find the enclosing `BrowserPaneContainer`.
    /// Unlike `enclosingPaneLeaf()`, this works even when SwiftUI has
    /// re-parented the container out of PaneLeaf (via `NSViewRepresentable`).
    func enclosingBrowserContainer() -> BrowserPaneContainer? {
        var v: NSView? = self
        while let cur = v {
            if let c = cur as? BrowserPaneContainer { return c }
            v = cur.superview
        }
        return nil
    }
}
