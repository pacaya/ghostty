import Foundation
import SwiftUI

/// View-model backing the project editor sheet. Holds a mutable copy of a
/// project's layout tree while the sheet is open, exposes a DFS-flattened
/// leaf list for sidebar selection, and commits edits back to the store on
/// save.
///
/// `IndexPath` convention: each step is `0` for the left/top child and `1`
/// for the right/bottom child of a split. An empty path refers to the root
/// node.
@MainActor
final class ProjectEditorModel: ObservableObject {
    typealias ProjectLeaf = ProjectLayoutNode.ProjectLeaf

    @Published var editedLayout: ProjectLayoutNode
    @Published var selection: IndexPath?

    private var project: Project

    init(project: Project) {
        self.project = project
        self.editedLayout = project.layoutRoot
        self.selection = Self.firstLeafPath(in: project.layoutRoot)
    }

    /// DFS-flattened list of leaves in the current edited layout, left/top
    /// before right/bottom. Each entry carries the `IndexPath` that addresses
    /// the leaf in the tree.
    var flatLeaves: [(indexPath: IndexPath, leaf: ProjectLeaf)] {
        var result: [(IndexPath, ProjectLeaf)] = []
        Self.collectLeaves(node: editedLayout, path: IndexPath(), into: &result)
        return result
    }

    /// Returns the leaf at the given index path, or `nil` if the path does
    /// not resolve to a leaf.
    func leaf(at indexPath: IndexPath) -> ProjectLeaf? {
        Self.node(in: editedLayout, at: indexPath).flatMap {
            if case .leaf(let leaf) = $0 { return leaf } else { return nil }
        }
    }

    /// Applies `transform` to the leaf at `indexPath`, rebuilding the tree
    /// along the path. Splits on the path retain their direction, ratio, and
    /// sibling subtrees. No-ops silently if the path does not resolve to a
    /// leaf.
    func updateLeaf(at indexPath: IndexPath, transform: (inout ProjectLeaf) -> Void) {
        guard let updated = Self.rebuild(node: editedLayout, path: indexPath, transform: transform) else {
            return
        }
        // Skip the @Published broadcast when nothing actually changed so
        // every keystroke doesn't invalidate the minimap / pane list.
        guard updated != editedLayout else { return }
        editedLayout = updated
    }

    /// Normalizes editor fields, stamps `lastModified`, and writes the
    /// updated project back to `store`.
    func save(to store: ProjectStore) {
        let normalized = Self.normalize(editedLayout)
        var updated = project
        updated.layoutRoot = normalized
        updated.lastModified = Date()
        store.updateProject(updated)
        project = updated
        if normalized != editedLayout {
            editedLayout = normalized
        }
    }

    // MARK: - Tree helpers

    private static func firstLeafPath(in node: ProjectLayoutNode) -> IndexPath? {
        switch node {
        case .leaf:
            return IndexPath()
        case .split(let split):
            if let left = firstLeafPath(in: split.left) {
                return IndexPath(index: 0).appending(left)
            }
            if let right = firstLeafPath(in: split.right) {
                return IndexPath(index: 1).appending(right)
            }
            return nil
        }
    }

    private static func collectLeaves(
        node: ProjectLayoutNode,
        path: IndexPath,
        into result: inout [(IndexPath, ProjectLeaf)]
    ) {
        switch node {
        case .leaf(let leaf):
            result.append((path, leaf))
        case .split(let split):
            collectLeaves(node: split.left, path: path.appending(0), into: &result)
            collectLeaves(node: split.right, path: path.appending(1), into: &result)
        }
    }

    private static func node(in node: ProjectLayoutNode, at path: IndexPath) -> ProjectLayoutNode? {
        guard let step = path.first else { return node }
        guard case .split(let split) = node else { return nil }
        let remainder = path.dropFirst()
        switch step {
        case 0: return self.node(in: split.left, at: remainder)
        case 1: return self.node(in: split.right, at: remainder)
        default: return nil
        }
    }

    private static func rebuild(
        node: ProjectLayoutNode,
        path: IndexPath,
        transform: (inout ProjectLeaf) -> Void
    ) -> ProjectLayoutNode? {
        if path.isEmpty {
            guard case .leaf(var leaf) = node else { return nil }
            transform(&leaf)
            return .leaf(leaf)
        }
        guard case .split(let split) = node else { return nil }
        let step = path[0]
        let remainder = path.dropFirst()
        switch step {
        case 0:
            guard let newLeft = rebuild(node: split.left, path: remainder, transform: transform) else {
                return nil
            }
            return .split(.init(
                direction: split.direction,
                ratio: split.ratio,
                left: newLeft,
                right: split.right
            ))
        case 1:
            guard let newRight = rebuild(node: split.right, path: remainder, transform: transform) else {
                return nil
            }
            return .split(.init(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left,
                right: newRight
            ))
        default:
            return nil
        }
    }

    /// Collapses empty strings in `command`/`initialInput` to `nil` and
    /// drops empty-keyed entries from `environmentVariables` across every
    /// leaf in the tree.
    private static func normalize(_ node: ProjectLayoutNode) -> ProjectLayoutNode {
        switch node {
        case .leaf(let leaf):
            let command = leaf.command?.isEmpty == true ? nil : leaf.command
            let initialInput = leaf.initialInput?.isEmpty == true ? nil : leaf.initialInput
            let env = leaf.environmentVariables.filter { !$0.key.isEmpty }
            let normalized = ProjectLeaf(
                workingDirectory: leaf.workingDirectory,
                kind: leaf.kind,
                url: leaf.url,
                id: leaf.id,
                command: command,
                initialInput: initialInput,
                environmentVariables: env
            )
            return .leaf(normalized)
        case .split(let split):
            return .split(.init(
                direction: split.direction,
                ratio: split.ratio,
                left: normalize(split.left),
                right: normalize(split.right)
            ))
        }
    }
}
