import AppKit
import Foundation

/// Menu commands and shared helpers for creating browser panes.
enum BrowserCommands {
    /// Default URL opened when a new browser split is requested without an
    /// explicit destination (menu items, keybindings).
    static let defaultURL = URL(string: "about:blank")!

    /// Core browser-split spawn helper. Browser panes live entirely inside
    /// the Swift apprt — this never touches libghostty. Callers pass an
    /// explicit `anchor` leaf so IPC-originated spawns don't race against
    /// `focusedLeaf` drift.
    @discardableResult
    static func spawnBrowserSplit(
        from sourceController: BaseTerminalController,
        anchor: PaneLeaf,
        url: URL,
        direction: SplitTree<PaneLeaf>.NewDirection
    ) -> PaneLeaf? {
        // The anchor must still exist in the source controller's tree.
        guard sourceController.surfaceTree.contains(where: { $0 === anchor }) else {
            return nil
        }

        let container = BrowserPaneContainer(url: url)
        let newLeaf = PaneLeaf(browser: container)

        let newTree: SplitTree<PaneLeaf>
        do {
            newTree = try sourceController.surfaceTree.inserting(
                view: newLeaf,
                at: anchor,
                direction: direction)
        } catch {
            return nil
        }

        sourceController.replaceSurfaceTree(
            newTree,
            moveFocusToLeaf: newLeaf,
            moveFocusFromLeaf: anchor,
            undoAction: "New Browser Split")

        // Focus the newly created browser pane's web view.
        DispatchQueue.main.async {
            newLeaf.window?.makeFirstResponder(newLeaf)
        }

        return newLeaf
    }
}

// MARK: - BaseTerminalController @IBActions

extension BaseTerminalController {
    /// Resolve the anchor leaf for a menu-initiated browser split. Prefer
    /// the actually-focused leaf; fall back to the first leaf in the tree
    /// so a browser split is still created in an otherwise idle window.
    fileprivate var browserSplitAnchor: PaneLeaf? {
        focusedLeaf ?? surfaceTree.root?.leftmostLeaf()
    }

    fileprivate func performBrowserSplit(_ direction: SplitTree<PaneLeaf>.NewDirection) {
        guard let anchor = browserSplitAnchor else { return }
        BrowserCommands.spawnBrowserSplit(
            from: self,
            anchor: anchor,
            url: BrowserCommands.defaultURL,
            direction: direction)
    }

    @IBAction func newBrowserSplitRight(_ sender: Any?) { performBrowserSplit(.right) }
    @IBAction func newBrowserSplitLeft(_ sender: Any?) { performBrowserSplit(.left) }
    @IBAction func newBrowserSplitDown(_ sender: Any?) { performBrowserSplit(.down) }
    @IBAction func newBrowserSplitUp(_ sender: Any?) { performBrowserSplit(.up) }
}

