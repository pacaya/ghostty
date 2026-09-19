import Foundation

/// A lightweight tree describing split geometry and working directories.
/// Mirrors `SplitTree<Ghostty.SurfaceView>.Node` but stores only the data needed to
/// reconstruct a layout, not live NSView references.
indirect enum ProjectLayoutNode: Codable, Equatable {
    case leaf(ProjectLeaf)
    case split(ProjectSplit)

    struct ProjectLeaf: Codable, Equatable {
        /// Stable identifier for this leaf. Round-trips through persistence so
        /// that a rebuilt `SurfaceView` keeps the same
        /// id it had before the snapshot, which lets callers correlate leaves
        /// across edits and relaunches.
        let id: UUID

        /// Working directory for the terminal.
        var workingDirectory: String

        /// True when decoded from a `"kind": "browser"` leaf written by builds
        /// that had browser panes. Never encoded; such leaves are removed by
        /// `droppingLegacyBrowserLeaves()` when projects are loaded.
        let isLegacyBrowser: Bool

        /// Optional command to run after the shell loads. Sent as raw input
        /// to the PTY; a trailing newline is appended at launch time so the
        /// user's shell executes it.
        var initialInput: String?

        /// Environment variables merged into the terminal's launch environment.
        /// Empty dictionary means "no overrides."
        var environmentVariables: [String: String]

        init(
            workingDirectory: String,
            id: UUID = UUID(),
            initialInput: String? = nil,
            environmentVariables: [String: String] = [:]
        ) {
            self.workingDirectory = workingDirectory
            self.isLegacyBrowser = false
            self.id = id
            self.initialInput = initialInput
            self.environmentVariables = environmentVariables
        }

        enum CodingKeys: String, CodingKey {
            case id
            case workingDirectory
            case kind
            case command
            case initialInput
            case environmentVariables
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
            workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory) ?? "~"
            isLegacyBrowser = try container.decodeIfPresent(String.self, forKey: .kind) == "browser"
            // Migrate older snapshots that persisted this text under "command".
            let legacyCommand = try container.decodeIfPresent(String.self, forKey: .command)
            initialInput = try container.decodeIfPresent(String.self, forKey: .initialInput) ?? legacyCommand
            environmentVariables = try container.decodeIfPresent(
                [String: String].self, forKey: .environmentVariables) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(id, forKey: .id)
            try container.encode(workingDirectory, forKey: .workingDirectory)
            // Normalize empty strings to omitted keys so JSON stays tidy and
            // matches libghostty's "unset → inherit" contract.
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
    /// leaf ids are reused as the live `SurfaceView`
    /// UUID — sharing them across copies breaks app-global lookups like
    /// `AppDelegate.findSurface(forUUID:)` when both copies are open.
    func withRegeneratedLeafIDs() -> ProjectLayoutNode {
        switch self {
        case .leaf(let leaf):
            return .leaf(ProjectLeaf(
                workingDirectory: leaf.workingDirectory,
                id: UUID(),
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

    /// Return a copy without leaves that were browser panes, collapsing each
    /// affected split into its remaining child. A layout made only of browser
    /// leaves becomes a single terminal in the home directory.
    func droppingLegacyBrowserLeaves() -> ProjectLayoutNode {
        prunedOfLegacyBrowserLeaves() ?? .leaf(ProjectLeaf(workingDirectory: "~"))
    }

    private func prunedOfLegacyBrowserLeaves() -> ProjectLayoutNode? {
        switch self {
        case .leaf(let leaf):
            return leaf.isLegacyBrowser ? nil : self
        case .split(let split):
            let left = split.left.prunedOfLegacyBrowserLeaves()
            let right = split.right.prunedOfLegacyBrowserLeaves()
            guard let left else { return right }
            guard let right else { return left }
            return .split(ProjectSplit(
                direction: split.direction,
                ratio: split.ratio,
                left: left,
                right: right
            ))
        }
    }

    /// Return a copy with `initialInput` and `environmentVariables` cleared
    /// from every leaf. Used on import: those fields drive what the shell
    /// runs and the environment it runs in, so a shared project file would
    /// otherwise be a code-execution surface. Users can re-add them
    /// explicitly via the project editor if they trust the source.
    func strippingExecutableFields() -> ProjectLayoutNode {
        switch self {
        case .leaf(let leaf):
            return .leaf(ProjectLeaf(
                workingDirectory: leaf.workingDirectory,
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

/// Editor-mutable subset of `ProjectLeaf` fields — the ones not derivable from
/// a live split tree and which need to round-trip through operations like
/// `merging(editorFieldsFrom:)` and window-state restoration.
struct ProjectLeafEditorFields: Codable, Equatable {
    var initialInput: String?
    var environmentVariables: [String: String]
}

struct ProjectsFile: Codable {
    static let currentVersion = 1
    var version: Int = Self.currentVersion
    var folders: [ProjectFolder]
    var projects: [Project]
}
