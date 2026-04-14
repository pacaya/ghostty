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
                    url: nil,
                    id: paneLeaf.id
                ))
            } else if let browser = paneLeaf.browser {
                return .leaf(ProjectLeaf(
                    workingDirectory: "~",
                    kind: .browser,
                    url: browser.url?.absoluteString ?? BrowserCommands.defaultURL.absoluteString,
                    id: paneLeaf.id
                ))
            } else {
                return .leaf(ProjectLeaf(workingDirectory: "~", id: paneLeaf.id))
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
                config.command = leaf.command
                config.initialInput = leaf.initialInput
                config.environmentVariables = leaf.environmentVariables
                let view = Ghostty.SurfaceView(app, baseConfig: config, uuid: leaf.id)
                return .leaf(view: PaneLeaf(terminal: view))
            case .browser:
                let url = leaf.url.flatMap(URL.init(string:)) ?? BrowserCommands.defaultURL
                let container = BrowserPaneContainer(url: url, id: leaf.id)
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

    /// Editor-only fields carried by a `ProjectLeaf` that aren't recoverable
    /// from the live split tree — used by `merging(editorFieldsFrom:)` to
    /// preserve these across snapshot writes.
    private struct EditorFields {
        var command: String?
        var initialInput: String?
        var environmentVariables: [String: String]
    }

    /// Return a new layout whose leaves inherit editor-only fields (`command`,
    /// `initialInput`, `environmentVariables`) from leaves in `old` that share
    /// the same `ProjectLeaf.id`. Split structure and live-derived fields
    /// (working directory, URL) are preserved from `self`.
    func merging(editorFieldsFrom old: ProjectLayoutNode) -> ProjectLayoutNode {
        var map: [UUID: EditorFields] = [:]
        old.collectEditorFields(into: &map)
        return applyingEditorFields(map)
    }

    private func collectEditorFields(into map: inout [UUID: EditorFields]) {
        switch self {
        case .leaf(let leaf):
            // First match wins — skip if this id is already recorded.
            if map[leaf.id] == nil {
                map[leaf.id] = EditorFields(
                    command: leaf.command,
                    initialInput: leaf.initialInput,
                    environmentVariables: leaf.environmentVariables
                )
            }
        case .split(let split):
            split.left.collectEditorFields(into: &map)
            split.right.collectEditorFields(into: &map)
        }
    }

    private func applyingEditorFields(_ map: [UUID: EditorFields]) -> ProjectLayoutNode {
        switch self {
        case .leaf(let leaf):
            let fields = map[leaf.id]
            return .leaf(ProjectLeaf(
                workingDirectory: leaf.workingDirectory,
                kind: leaf.kind,
                url: leaf.url,
                id: leaf.id,
                command: fields?.command,
                initialInput: fields?.initialInput,
                environmentVariables: fields?.environmentVariables ?? [:]
            ))
        case .split(let split):
            return .split(ProjectSplit(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.applyingEditorFields(map),
                right: split.right.applyingEditorFields(map)
            ))
        }
    }
}
