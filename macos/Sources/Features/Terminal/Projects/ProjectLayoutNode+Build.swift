import Cocoa
import GhosttyKit

extension ProjectLayoutNode {
    /// Snapshot a live split tree into a lightweight layout blueprint.
    static func from(tree: SplitTree<Ghostty.SurfaceView>) -> ProjectLayoutNode? {
        guard let root = tree.root else { return nil }
        return from(node: root)
    }

    private static func from(node: SplitTree<Ghostty.SurfaceView>.Node) -> ProjectLayoutNode {
        switch node {
        case .leaf(let view):
            return .leaf(ProjectLeaf(
                workingDirectory: view.pwd ?? "~"
            ))
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
    /// Each leaf creates a new SurfaceView with its working directory set.
    func buildSplitTree(app: ghostty_app_t) -> SplitTree<Ghostty.SurfaceView> {
        guard let root = buildNode(app: app) else {
            return SplitTree()
        }
        return SplitTree(root: root, zoomed: nil)
    }

    private func buildNode(app: ghostty_app_t) -> SplitTree<Ghostty.SurfaceView>.Node? {
        switch self {
        case .leaf(let leaf):
            var config = Ghostty.SurfaceConfiguration()
            config.workingDirectory = leaf.workingDirectory
            let view = Ghostty.SurfaceView(app, baseConfig: config, uuid: UUID())
            return .leaf(view: view)

        case .split(let split):
            guard let left = split.left.buildNode(app: app),
                  let right = split.right.buildNode(app: app) else {
                return nil
            }
            let direction: SplitTree<Ghostty.SurfaceView>.Direction =
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
