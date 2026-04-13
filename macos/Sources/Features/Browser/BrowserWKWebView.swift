import AppKit
import WebKit

/// WKWebView subclass used inside browser panes.
///
/// Exists for two reasons that both stem from WebKit being an opaque sibling
/// of the rest of the split-tree machinery:
///
/// 1. When the user clicks anywhere inside the web content, AppKit makes the
///    web view the first responder directly. That bypasses
///    `PaneLeaf.becomeFirstResponder`, so the controller's focus cache keeps
///    pointing at whichever terminal was focused before — and every leaf-aware
///    action (close, split, zoom, …) then targets the wrong leaf. We fix that
///    by bubbling a focus notification up the view chain on first-responder
///    acquisition.
///
/// 2. Terminal panes close on Ctrl+D via the shell's EOF handling. A browser
///    pane has no shell, so we translate Ctrl+D directly into the controller's
///    close action here rather than wiring a global binding that would need to
///    know which leaf kind is focused.
final class BrowserWKWebView: WKWebView {
    override func becomeFirstResponder() -> Bool {
        enclosingBrowserContainer()?.notifyControllerOfFocus()
        return super.becomeFirstResponder()
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.type == .keyDown else { return super.performKeyEquivalent(with: event) }

        // WKWebView's base performKeyEquivalent claims to handle standard
        // editing shortcuts but does not actually perform the edit action
        // through the web content process. Dispatch the corresponding
        // NSResponder action directly — the same mechanism the context menu
        // uses — so the web view processes it through WebKit.
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command {
            if let chars = event.charactersIgnoringModifiers?.lowercased() {
                let action: Selector? = switch chars {
                case "c": #selector(NSText.copy(_:))
                case "v": #selector(NSText.paste(_:))
                case "x": #selector(NSText.cut(_:))
                case "a": #selector(NSText.selectAll(_:))
                default: nil
                }
                if let action {
                    NSApp.sendAction(action, to: nil, from: self)
                    return true
                }
            }
        }

        return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .control,
           event.charactersIgnoringModifiers == "d",
           let controller = window?.windowController as? BaseTerminalController {
            controller.close(self)
            return
        }
        super.keyDown(with: event)
    }

}
