import Foundation

/// A lightweight tree describing split geometry and working directories.
/// Mirrors `SplitTree<PaneLeaf>.Node` but stores only the data needed to
/// reconstruct a layout, not live NSView references.
indirect enum ProjectLayoutNode: Codable, Equatable {
    case leaf(ProjectLeaf)
    case split(ProjectSplit)

    enum ProjectLeafKind: String, Codable, Equatable {
        case terminal
        case browser
    }

    struct ProjectLeaf: Codable, Equatable {
        /// Working directory for a terminal leaf. Ignored for browser leaves.
        let workingDirectory: String

        /// Leaf kind. Defaults to `.terminal` when absent in persisted JSON
        /// so older project files continue to decode.
        let kind: ProjectLeafKind

        /// URL for a browser leaf. `nil` for terminal leaves.
        let url: String?

        init(workingDirectory: String, kind: ProjectLeafKind = .terminal, url: String? = nil) {
            self.workingDirectory = workingDirectory
            self.kind = kind
            self.url = url
        }

        enum CodingKeys: String, CodingKey {
            case workingDirectory
            case kind
            case url
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? "~"
            kind = try container.decodeIfPresent(ProjectLeafKind.self, forKey: .kind) ?? .terminal
            url = try container.decodeIfPresent(String.self, forKey: .url)
        }
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
    /// Whether this folder is expanded in the sidebar. Persisted across sessions.
    var isExpanded: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, parentId, sortOrder, isExpanded
    }

    init(id: UUID, name: String, parentId: UUID? = nil, sortOrder: Int, isExpanded: Bool = true) {
        self.id = id
        self.name = name
        self.parentId = parentId
        self.sortOrder = sortOrder
        self.isExpanded = isExpanded
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
        sortOrder = try container.decode(Int.self, forKey: .sortOrder)
        isExpanded = try container.decodeIfPresent(Bool.self, forKey: .isExpanded) ?? true
    }
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
