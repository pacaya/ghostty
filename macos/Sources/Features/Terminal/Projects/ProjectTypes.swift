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
        /// Stable identifier for this leaf. Round-trips through persistence so
        /// that a rebuilt `SurfaceView` / `BrowserPaneContainer` keeps the same
        /// id it had before the snapshot, which lets callers correlate leaves
        /// across edits and relaunches.
        let id: UUID

        /// Working directory for a terminal leaf. Ignored for browser leaves.
        var workingDirectory: String

        /// Leaf kind. Defaults to `.terminal` when absent in persisted JSON
        /// so older project files continue to decode.
        var kind: ProjectLeafKind

        /// URL for a browser leaf. `nil` for terminal leaves.
        var url: String?

        /// Optional command override for a terminal leaf. `nil` means inherit
        /// from the app config (libghostty's "unset → inherit" contract).
        var command: String?

        /// Optional initial input piped into the terminal on launch.
        var initialInput: String?

        /// Environment variables merged into the terminal's launch environment.
        /// Empty dictionary means "no overrides."
        var environmentVariables: [String: String]

        init(
            workingDirectory: String,
            kind: ProjectLeafKind = .terminal,
            url: String? = nil,
            id: UUID = UUID(),
            command: String? = nil,
            initialInput: String? = nil,
            environmentVariables: [String: String] = [:]
        ) {
            self.workingDirectory = workingDirectory
            self.kind = kind
            self.url = url
            self.id = id
            self.command = command
            self.initialInput = initialInput
            self.environmentVariables = environmentVariables
        }

        enum CodingKeys: String, CodingKey {
            case id
            case workingDirectory
            case kind
            case url
            case command
            case initialInput
            case environmentVariables
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? "~"
            kind = try container.decodeIfPresent(ProjectLeafKind.self, forKey: .kind) ?? .terminal
            url = try container.decodeIfPresent(String.self, forKey: .url)
            command = try container.decodeIfPresent(String.self, forKey: .command)
            initialInput = try container.decodeIfPresent(String.self, forKey: .initialInput)
            environmentVariables = try container.decodeIfPresent(
                [String: String].self, forKey: .environmentVariables) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(workingDirectory, forKey: .workingDirectory)
            try container.encode(kind, forKey: .kind)
            // Normalize empty strings to omitted keys so JSON stays tidy and
            // matches libghostty's "unset → inherit" contract.
            if let url, !url.isEmpty {
                try container.encode(url, forKey: .url)
            }
            if let command, !command.isEmpty {
                try container.encode(command, forKey: .command)
            }
            if let initialInput, !initialInput.isEmpty {
                try container.encode(initialInput, forKey: .initialInput)
            }
            if !environmentVariables.isEmpty {
                try container.encode(environmentVariables, forKey: .environmentVariables)
            }
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

    /// Return a copy of the tree with every `ProjectLeaf.id` replaced with a
    /// fresh UUID. Required when cloning a layout (duplicate/import) because
    /// leaf ids are reused as the live `SurfaceView` / `BrowserPaneContainer`
    /// UUID — sharing them across copies breaks app-global lookups like
    /// `AppDelegate.findSurface(forUUID:)` when both copies are open.
    func withRegeneratedLeafIDs() -> ProjectLayoutNode {
        switch self {
        case .leaf(let leaf):
            return .leaf(ProjectLeaf(
                workingDirectory: leaf.workingDirectory,
                kind: leaf.kind,
                url: leaf.url,
                id: UUID(),
                command: leaf.command,
                initialInput: leaf.initialInput,
                environmentVariables: leaf.environmentVariables
            ))
        case .split(let split):
            return .split(ProjectSplit(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.withRegeneratedLeafIDs(),
                right: split.right.withRegeneratedLeafIDs()
            ))
        }
    }

    /// Return a copy with `command`, `initialInput`, and `environmentVariables`
    /// cleared from every leaf. Used on import: those fields drive process
    /// launch and environment, so a shared project file would otherwise be a
    /// code-execution surface. Users can re-add them explicitly via the
    /// project editor if they trust the source.
    func strippingExecutableFields() -> ProjectLayoutNode {
        switch self {
        case .leaf(let leaf):
            return .leaf(ProjectLeaf(
                workingDirectory: leaf.workingDirectory,
                kind: leaf.kind,
                url: leaf.url,
                id: leaf.id
            ))
        case .split(let split):
            return .split(ProjectSplit(
                direction: split.direction,
                ratio: split.ratio,
                left: split.left.strippingExecutableFields(),
                right: split.right.strippingExecutableFields()
            ))
        }
    }
}

struct ProjectsFile: Codable {
    static let currentVersion = 1
    var version: Int = Self.currentVersion
    var folders: [ProjectFolder]
    var projects: [Project]
}
