import Foundation

/// A lightweight tree describing split geometry and working directories.
/// Mirrors `SplitTree<Ghostty.SurfaceView>.Node` but stores only the data
/// needed to reconstruct a layout, not live NSView references.
indirect enum ProjectLayoutNode: Codable, Equatable {
    case leaf(ProjectLeaf)
    case split(ProjectSplit)

    struct ProjectLeaf: Codable, Equatable {
        let workingDirectory: String
    }

    struct ProjectSplit: Codable, Equatable {
        let direction: ProjectSplitDirection
        let ratio: Double
        let left: ProjectLayoutNode
        let right: ProjectLayoutNode
    }
}

enum ProjectSplitDirection: String, Codable, Equatable {
    case horizontal
    case vertical
}

struct Project: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var color: TerminalTabColor
    var layoutRoot: ProjectLayoutNode
    var lastModified: Date
    /// The folder this project belongs to. nil means root level.
    var folderId: UUID?
    /// Display order among siblings for drag-drop reordering.
    var sortOrder: Int
}

struct ProjectFolder: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    /// Parent folder ID. nil means root level.
    var parentId: UUID?
    /// Display order among siblings for drag-drop reordering.
    var sortOrder: Int
}

extension ProjectLayoutNode {
    /// Number of leaf panes in this layout tree.
    var leafCount: Int {
        switch self {
        case .leaf:
            return 1
        case .split(let split):
            return split.left.leafCount + split.right.leafCount
        }
    }
}

struct ProjectsFile: Codable {
    static let currentVersion = 1
    var version: Int = Self.currentVersion
    var folders: [ProjectFolder]
    var projects: [Project]
}
