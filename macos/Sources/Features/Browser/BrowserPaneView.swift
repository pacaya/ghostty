import AppKit
import Combine
import WebKit

/// An `NSView` subclass that hosts a `WKWebView` for a browser pane leaf.
///
/// This is the actual web-view host. It is composed inside a `BrowserPaneContainer`
/// (which adds the chrome strip on top) before being wrapped in a `PaneLeaf` and
/// placed into the split tree.
class BrowserPaneView: NSView, ObservableObject, Identifiable {
    typealias ID = UUID

    /// Stable identifier used by the split tree and for restoration.
    let id: UUID

    let webView: BrowserWKWebView

    // MARK: - Observable Properties

    @Published private(set) var title: String = ""
    @Published private(set) var url: URL?
    @Published private(set) var canGoBack: Bool = false
    @Published private(set) var canGoForward: Bool = false
    @Published private(set) var estimatedProgress: Double = 0
    @Published private(set) var isLoading: Bool = false

    // MARK: - KVO

    private var titleObservation: NSKeyValueObservation?
    private var urlObservation: NSKeyValueObservation?
    private var canGoBackObservation: NSKeyValueObservation?
    private var canGoForwardObservation: NSKeyValueObservation?
    private var progressObservation: NSKeyValueObservation?
    private var loadingObservation: NSKeyValueObservation?

    // MARK: - Init

    init(url: URL, id: UUID) {
        self.id = id

        let configuration = WKWebViewConfiguration()
        configuration.userContentController = Self.makeUserContentController()
        self.webView = BrowserWKWebView(frame: .zero, configuration: configuration)

        // Safari user agent so sites that sniff UA behave sensibly.
        self.webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) " +
            "AppleWebKit/605.1.15 (KHTML, like Gecko) " +
            "Version/17.0 Safari/605.1.15"

        super.init(frame: NSRect(x: 0, y: 0, width: 800, height: 600))

        setupWebView()
        observeWebView()

        self.load(url: url)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    deinit {
        titleObservation?.invalidate()
        urlObservation?.invalidate()
        canGoBackObservation?.invalidate()
        canGoForwardObservation?.invalidate()
        progressObservation?.invalidate()
        loadingObservation?.invalidate()
        webView.stopLoading()
    }

    // MARK: - Setup

    private static func makeUserContentController() -> WKUserContentController {
        let controller = WKUserContentController()
        controller.add(BrowserPaneCloseMessageHandler.shared, name: BrowserPaneCloseMessageHandler.name)
        controller.addUserScript(BrowserPaneCloseMessageHandler.userScript)
        return controller
    }

    private func setupWebView() {
        webView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: topAnchor),
            webView.leadingAnchor.constraint(equalTo: leadingAnchor),
            webView.bottomAnchor.constraint(equalTo: bottomAnchor),
            webView.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    private func observeWebView() {
        titleObservation = webView.observe(\.title, options: [.initial, .new]) { [weak self] webView, _ in
            self?.title = webView.title ?? ""
        }
        urlObservation = webView.observe(\.url, options: [.initial, .new]) { [weak self] webView, _ in
            self?.url = webView.url
        }
        canGoBackObservation = webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self] webView, _ in
            self?.canGoBack = webView.canGoBack
        }
        canGoForwardObservation = webView.observe(\.canGoForward, options: [.initial, .new]) { [weak self] webView, _ in
            self?.canGoForward = webView.canGoForward
        }
        progressObservation = webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self] webView, _ in
            self?.estimatedProgress = webView.estimatedProgress
        }
        loadingObservation = webView.observe(\.isLoading, options: [.initial, .new]) { [weak self] webView, _ in
            self?.isLoading = webView.isLoading
        }
    }

    // MARK: - Navigation

    func load(url: URL) {
        webView.load(URLRequest(url: url))
    }

    func goBack() {
        webView.goBack()
    }

    func goForward() {
        webView.goForward()
    }

    func reload() {
        webView.reload()
    }

    func stopLoading() {
        webView.stopLoading()
    }

    // MARK: - Responder Chain

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        enclosingBrowserContainer()?.notifyControllerOfFocus()
        return window?.makeFirstResponder(webView) ?? false
    }

    /// Let Ghostty's key bindings claim the event before WKWebView sees it.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        return super.performKeyEquivalent(with: event)
    }
}
