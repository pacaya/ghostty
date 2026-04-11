import Cocoa
import GhosttyKit

extension ProjectLayoutNode {
    /// Snapshot a live split tree into a lightweight layout blueprint.
    static func from(tree: SplitTree<PaneLeaf>) -> ProjectLayoutNode? {
        guard let root = tree.root else { return nil }
        return from(node: root)
    }

    private static func from(node: SplitTree<PaneLeaf>.Node) -> ProjectLayoutNode {
        switch node {
        case .leaf(let paneLeaf):
            if let terminal = paneLeaf.terminal {
                return .leaf(ProjectLeaf(
                    workingDirectory: terminal.pwd ?? "~",
                    kind: .terminal,
                    url: nil
                ))
            } else if let browser = paneLeaf.browser {
                return .leaf(ProjectLeaf(
                    workingDirectory: "~",
                    kind: .browser,
                    url: browser.url?.absoluteString ?? BrowserCommands.defaultURL.absoluteString
                ))
            } else {
                return .leaf(ProjectLeaf(workingDirectory: "~"))
            }
        case .split(let split):
            let direction: ProjectSplitDirection = split.direction == .horizontal ? .horizontal : .vertical
            return .split(ProjectSplit(
                direction: direction,
                ratio: split.ratio,
                left: from(node: split.left),
                right: from(node: split.right)
            ))
        }
    }

    /// Reconstruct a live split tree from this blueprint.
    /// Each leaf creates a new SurfaceView with its working directory set,
    /// or a new BrowserPaneContainer for browser leaves.
    func buildSplitTree(app: ghostty_app_t) -> SplitTree<PaneLeaf> {
        guard let root = buildNode(app: app) else {
            return SplitTree()
        }
        return SplitTree(root: root, zoomed: nil)
    }

    private func buildNode(app: ghostty_app_t) -> SplitTree<PaneLeaf>.Node? {
        switch self {
        case .leaf(let leaf):
            switch leaf.kind {
            case .terminal:
                var config = Ghostty.SurfaceConfiguration()
                config.workingDirectory = leaf.workingDirectory
                let view = Ghostty.SurfaceView(app, baseConfig: config, uuid: UUID())
                return .leaf(view: PaneLeaf(terminal: view))
            case .browser:
                let url = leaf.url.flatMap(URL.init(string:)) ?? BrowserCommands.defaultURL
                let container = BrowserPaneContainer(url: url)
                return .leaf(view: PaneLeaf(browser: container))
            }

        case .split(let split):
            guard let left = split.left.buildNode(app: app),
                  let right = split.right.buildNode(app: app) else {
                return nil
            }
            let direction: SplitTree<PaneLeaf>.Direction =
                split.direction == .horizontal ? .horizontal : .vertical
            return .split(.init(
                direction: direction,
                ratio: split.ratio,
                left: left,
                right: right
            ))
        }
    }
}
