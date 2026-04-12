import AppKit
import WebKit

/// Receives the `window.close()` bridge message from an injected user script
/// and closes the owning browser pane.
///
/// WebKit only fires `WKUIDelegate.webViewDidClose(_:)` for web views created
/// via `createWebViewWith` (i.e. JS `window.open`). Our panes load pages
/// directly with `WKWebView.load(URLRequest:)`, so a raw `window.close()` from
/// the page is a silent no-op. A user script injected at document start
/// replaces `window.close` with a `postMessage` bridge that lands here.
///
/// Stateless on purpose: `WKUserContentController` retains its handlers, so we
/// recover the pane from `message.webView` instead of holding a back-reference.
final class BrowserPaneCloseMessageHandler: NSObject, WKScriptMessageHandler {
    static let name = "ghosttyBrowserClose"

    static let shared = BrowserPaneCloseMessageHandler()

    static let userScript = WKUserScript(
        source: """
        (function() {
          window.close = function() {
            window.webkit.messageHandlers.\(BrowserPaneCloseMessageHandler.name).postMessage(null);
          };
        })();
        """,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
    )

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let webView = message.webView,
              let controller = webView.window?.windowController as? BaseTerminalController,
              let container = webView.enclosingPaneLeaf()?.browser,
              let node = controller.surfaceTree.root?.find(id: container.id)
        else { return }
        controller.closeSurface(node, withConfirmation: false)
    }
}
