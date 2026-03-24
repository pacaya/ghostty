import Cocoa
import Combine
import os

/// Manages the persisted collection of projects and their runtime association with open tabs.
@MainActor
final class ProjectStore: ObservableObject {
    static let shared = ProjectStore()

    private static let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.mitchellh.ghostty",
        category: "ProjectStore"
    )

    @Published private(set) var projects: [Project] = []
    @Published private(set) var folders: [ProjectFolder] = []

    /// Runtime-only mapping from open tab windows to project IDs.
    @Published private(set) var associations: [ObjectIdentifier: UUID] = [:]

    private var isDirty = false
    private var saveCancellable: AnyCancellable?

    /// The file URL for the projects JSON.
    private var fileURL: URL {
        let configDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config/ghostty")
        return configDir.appendingPathComponent("projects.json")
    }

    private init() {
        load()

        // Auto-save: debounce writes by 1 second after any change.
        saveCancellable = $projects.combineLatest($folders)
            .debounce(for: .seconds(1.0), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self, self.isDirty else { return }
                self.save()
            }
    }

    // MARK: - File I/O

    func load() {
        do {
            let data = try Data(contentsOf: fileURL)
            let file = try Self.decoder.decode(ProjectsFile.self, from: data)
            guard file.version == ProjectsFile.currentVersion else {
                Self.logger.warning("Skipping projects file with unknown version \(file.version)")
                return
            }
            self.projects = file.projects
            self.folders = file.folders
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // No projects file yet — this is expected on first launch.
        } catch {
            Self.logger.warning("Failed to load projects: \(error)")
        }
    }

    func save() {
        let file = ProjectsFile(folders: folders, projects: projects)
        do {
            let data = try Self.encoder.encode(file)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
            isDirty = false
        } catch {
            Self.logger.warning("Failed to save projects: \(error)")
        }
    }

    // MARK: - Project CRUD

    func addProject(_ project: Project) {
        projects.append(project)
        isDirty = true
    }

    func updateProject(_ project: Project) {
        guard let idx = projects.firstIndex(where: { $0.id == project.id }) else { return }
        guard projects[idx] != project else { return }
        projects[idx] = project
        isDirty = true
    }

    func updateProjectColor(_ projectId: UUID, to color: TerminalTabColor) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        guard projects[idx].color != color else { return }
        projects[idx].color = color
        projects[idx].lastModified = Date()
        isDirty = true
    }

    func deleteProject(id: UUID) {
        // Disassociate any open tab
        if let entry = associations.first(where: { $0.value == id }) {
            associations.removeValue(forKey: entry.key)
        }
        projects.removeAll { $0.id == id }
        isDirty = true
    }

    func duplicateProject(_ project: Project) -> Project {
        let copy = Project(
            id: UUID(),
            name: uniqueName(for: project.name, in: project.folderId),
            color: project.color,
            layoutRoot: project.layoutRoot,
            lastModified: Date(),
            folderId: project.folderId,
            sortOrder: nextSortOrder(in: project.folderId)
        )
        addProject(copy)
        return copy
    }

    func renameProject(_ projectId: UUID, to newName: String) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].name = newName
        projects[idx].lastModified = Date()
        isDirty = true

        // Sync to open tab if associated
        if let window = window(for: projectId) {
            (window.windowController as? BaseTerminalController)?.titleOverride = newName
        }
    }

    /// Generates a unique name like "Name (2)", "Name (3)", etc. among siblings.
    func uniqueName(for baseName: String, in folderId: UUID?) -> String {
        let existing = projects.filter { $0.folderId == folderId }.map(\.name)
        return Self.deduplicated(baseName, avoiding: existing)
    }

    // MARK: - Folder CRUD

    func addFolder(_ folder: ProjectFolder) {
        folders.append(folder)
        isDirty = true
    }

    func renameFolder(_ folderId: UUID, to newName: String) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        folders[idx].name = newName
        isDirty = true
    }

    func deleteFolder(id: UUID, recursive: Bool = false) {
        if recursive {
            let childFolderIds = folders.filter { $0.parentId == id }.map { $0.id }
            for childId in childFolderIds {
                deleteFolder(id: childId, recursive: true)
            }
            // Delete projects in this folder
            for project in projects where project.folderId == id {
                deleteProject(id: project.id)
            }
        } else {
            // Reparent children to this folder's parent
            let parentId = folders.first { $0.id == id }?.parentId
            for i in folders.indices where folders[i].parentId == id {
                folders[i].parentId = parentId
            }
            for i in projects.indices where projects[i].folderId == id {
                projects[i].folderId = parentId
            }
        }
        folders.removeAll { $0.id == id }
        isDirty = true
    }

    // MARK: - Reordering

    func moveProject(_ projectId: UUID, toFolder folderId: UUID?, atSortOrder sortOrder: Int? = nil) {
        guard let idx = projects.firstIndex(where: { $0.id == projectId }) else { return }
        projects[idx].folderId = folderId
        if let sortOrder {
            projects[idx].sortOrder = sortOrder
        }
        isDirty = true
    }

    func reorderProject(fromId sourceId: UUID, toId targetId: UUID, inFolder folderId: UUID?) {
        let items = folderId == nil ? rootProjects() : projects(in: folderId!)
        reorderItems(items, fromId: sourceId, toId: targetId) { id, sortOrder in
            if let idx = projects.firstIndex(where: { $0.id == id }) {
                projects[idx].sortOrder = sortOrder
            }
        }
        isDirty = true
    }

    func reorderFolder(fromId sourceId: UUID, toId targetId: UUID, inParent parentId: UUID?) {
        let items = parentId == nil ? rootFolders() : childFolders(of: parentId!)
        reorderItems(items, fromId: sourceId, toId: targetId) { id, sortOrder in
            if let idx = folders.firstIndex(where: { $0.id == id }) {
                folders[idx].sortOrder = sortOrder
            }
        }
        isDirty = true
    }

    /// Repositions a project relative to a target project, inserting before (.top) or after (.bottom).
    func insertProject(_ projectId: UUID, relativeTo targetId: UUID, edge: DropEdge, inFolder folderId: UUID?) {
        let siblings = folderId == nil ? rootProjects() : projects(in: folderId!)
        guard let targetIdx = siblings.firstIndex(where: { $0.id == targetId }) else { return }

        let insertIdx = edge == .top ? targetIdx : targetIdx + 1

        // Build ordered list, remove the project if already present, insert at correct position
        var orderedIds = siblings.map(\.id)
        orderedIds.removeAll { $0 == projectId }
        orderedIds.insert(projectId, at: min(insertIdx, orderedIds.count))

        // Reassign sort orders
        for (i, id) in orderedIds.enumerated() {
            if let idx = projects.firstIndex(where: { $0.id == id }) {
                projects[idx].sortOrder = i
            }
        }
        isDirty = true
    }

    /// Shared reorder algorithm: moves `sourceId` to the position of `targetId` and
    /// reassigns sort orders via the `apply` closure.
    private func reorderItems<T: Identifiable>(
        _ items: [T],
        fromId sourceId: T.ID,
        toId targetId: T.ID,
        apply: (T.ID, Int) -> Void
    ) {
        var mutable = items
        guard let sourceIdx = mutable.firstIndex(where: { $0.id == sourceId }),
              let targetIdx = mutable.firstIndex(where: { $0.id == targetId }) else { return }
        let item = mutable.remove(at: sourceIdx)
        mutable.insert(item, at: min(targetIdx, mutable.count))
        for (i, item) in mutable.enumerated() {
            apply(item.id, i)
        }
    }

    func moveFolder(_ folderId: UUID, toParent parentId: UUID?) {
        guard let idx = folders.firstIndex(where: { $0.id == folderId }) else { return }
        // Prevent circular nesting
        if let parentId, isDescendant(folderId: parentId, of: folderId) { return }
        folders[idx].parentId = parentId
        isDirty = true
    }

    // MARK: - Tab Association

    func associate(window: NSWindow, with projectId: UUID) {
        associations[ObjectIdentifier(window)] = projectId
    }

    func disassociate(window: NSWindow) {
        associations.removeValue(forKey: ObjectIdentifier(window))
    }

    func projectId(for window: NSWindow) -> UUID? {
        associations[ObjectIdentifier(window)]
    }

    func window(for projectId: UUID) -> NSWindow? {
        guard let entry = associations.first(where: { $0.value == projectId }) else {
            return nil
        }
        return NSApplication.shared.windows.first {
            ObjectIdentifier($0) == entry.key
        }
    }

    func isOpen(_ projectId: UUID) -> Bool {
        associations.values.contains(projectId)
    }

    /// Remove entries for windows that no longer exist.
    func purgeStale() {
        let liveWindows = Set(NSApplication.shared.windows.map { ObjectIdentifier($0) })
        for key in associations.keys where !liveWindows.contains(key) {
            associations.removeValue(forKey: key)
        }
    }

    /// Snapshot the current state of a tab into a new or existing project.
    func snapshotFromTab(
        controller: BaseTerminalController,
        existingProjectId: UUID? = nil
    ) -> Project? {
        guard let layoutRoot = ProjectLayoutNode.from(tree: controller.surfaceTree) else {
            return nil
        }
        let tabColor = (controller.window as? TerminalWindow)?.tabColor ?? .none
        let name = controller.titleOverride ?? controller.window?.title ?? "Untitled"

        if let existingId = existingProjectId,
           let idx = projects.firstIndex(where: { $0.id == existingId }) {
            projects[idx].layoutRoot = layoutRoot
            projects[idx].color = tabColor
            projects[idx].name = name
            projects[idx].lastModified = Date()
            isDirty = true
            return projects[idx]
        } else {
            let project = Project(
                id: UUID(),
                name: uniqueName(for: name, in: nil),
                color: tabColor,
                layoutRoot: layoutRoot,
                lastModified: Date(),
                folderId: nil,
                sortOrder: nextSortOrder(in: nil)
            )
            addProject(project)
            return project
        }
    }

    // MARK: - Import / Export

    func exportProjects(_ ids: [UUID]) -> Data? {
        let toExport = projects.filter { ids.contains($0.id) }
        let snippet = ProjectsFile(folders: [], projects: toExport)
        return try? Self.encoder.encode(snippet)
    }

    func importProjects(from data: Data) throws -> [Project] {
        let file = try Self.decoder.decode(ProjectsFile.self, from: data)
        var imported: [Project] = []
        for project in file.projects {
            let copy = Project(
                id: UUID(),
                name: uniqueName(for: project.name, in: nil),
                color: project.color,
                layoutRoot: project.layoutRoot,
                lastModified: Date(),
                folderId: nil,
                sortOrder: nextSortOrder(in: nil)
            )
            addProject(copy)
            imported.append(copy)
        }
        return imported
    }

    // MARK: - Helpers

    /// Returns the next sortOrder for items in the given folder.
    func nextSortOrder(in folderId: UUID?) -> Int {
        let maxProject = projects.filter { $0.folderId == folderId }.map(\.sortOrder).max() ?? -1
        let maxFolder = folders.filter { $0.parentId == folderId }.map(\.sortOrder).max() ?? -1
        return max(maxProject, maxFolder) + 1
    }

    /// Returns sorted root-level folders.
    func rootFolders() -> [ProjectFolder] {
        folders.filter { $0.parentId == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns sorted root-level projects (no folder).
    func rootProjects() -> [Project] {
        projects.filter { $0.folderId == nil }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns sorted child folders of a given parent.
    func childFolders(of parentId: UUID) -> [ProjectFolder] {
        folders.filter { $0.parentId == parentId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Returns sorted projects in a given folder.
    func projects(in folderId: UUID) -> [Project] {
        projects.filter { $0.folderId == folderId }.sorted { $0.sortOrder < $1.sortOrder }
    }

    /// Convenience for root-level sort order.
    func nextRootSortOrder() -> Int {
        nextSortOrder(in: nil)
    }

    /// Generates a unique folder name among siblings.
    func uniqueFolderName(for baseName: String, in parentId: UUID?) -> String {
        let existing = folders.filter { $0.parentId == parentId }.map(\.name)
        return Self.deduplicated(baseName, avoiding: existing)
    }

    /// Returns `baseName` if it doesn't collide, otherwise appends " (2)", " (3)", etc.
    private static func deduplicated(_ baseName: String, avoiding existing: [String]) -> String {
        var candidate = baseName
        var counter = 2
        while existing.contains(candidate) {
            candidate = "\(baseName) (\(counter))"
            counter += 1
        }
        return candidate
    }

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    /// Check if `folderId` is a descendant of `ancestorId` (prevents circular nesting).
    private func isDescendant(folderId: UUID, of ancestorId: UUID) -> Bool {
        var current: UUID? = folderId
        while let id = current {
            if id == ancestorId { return true }
            current = folders.first { $0.id == id }?.parentId
        }
        return false
    }
}
