import SwiftUI
import UniformTypeIdentifiers

/// Scrollable tree view of project folders and project items.
///
/// `dragState` is held as a `let` (not `@ObservedObject`) so this view does
/// not re-render on every drag tick — only the leaf `…DropIndicator`
/// wrappers observe `dragState`.
struct ProjectsListView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme
    let dragState: ProjectsDragState

    var body: some View {
        content
            .onDrop(of: [.ghosttySidebarItem], delegate: TabToProjectDropDelegate(
                projectStore: projectStore,
                tabManager: tabManager,
                targetFolderId: nil,
                dragState: dragState
            ))
    }

    @ViewBuilder
    private var content: some View {
        if projectStore.projects.isEmpty && projectStore.folders.isEmpty {
            // Empty state
            VStack(spacing: 4) {
                Spacer()
                Text("No projects yet")
                    .font(.system(size: 11))
                    .foregroundColor(theme.secondaryText)
                Text("Right-click a tab to save as project,\nor drag a tab here.")
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText.opacity(0.7))
                    .multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    // Root-level folders
                    ForEach(projectStore.rootFolders()) { folder in
                        FolderRowDropIndicator(
                            folder: folder,
                            projectStore: projectStore,
                            tabManager: tabManager,
                            theme: theme,
                            depth: 0,
                            dragState: dragState
                        )
                    }

                    // Root-level projects
                    ForEach(projectStore.rootProjects()) { project in
                        ProjectCardDropIndicator(
                            project: project,
                            projectStore: projectStore,
                            tabManager: tabManager,
                            theme: theme,
                            depth: 0,
                            dragState: dragState
                        )
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - FolderRowDropIndicator

/// Leaf wrapper that subscribes to `dragState` so only this view — not the
/// recursive folder tree above — re-renders when drag state changes.
struct FolderRowDropIndicator: View {
    let folder: ProjectFolder
    let projectStore: ProjectStore
    let tabManager: SidebarTabManager
    let theme: SidebarTheme
    let depth: Int
    @ObservedObject var dragState: ProjectsDragState

    var body: some View {
        ProjectFolderRow(
            folder: folder,
            projectStore: projectStore,
            tabManager: tabManager,
            theme: theme,
            depth: depth,
            dragState: dragState
        )
        .sidebarDropIndicator(
            itemID: folder.id,
            draggingID: dragState.draggingFolderUUID,
            dropTargetID: dragState.dropTargetFolderID
        )
        .onDrag {
            dragState.beginFolderDrag(folder.id)
            return SidebarDropPayload.folder(folder.id).itemProvider()
        }
        .onDrop(of: [.ghosttySidebarItem], delegate: FolderDropDelegate(
            projectStore: projectStore,
            currentFolder: folder,
            dragState: dragState
        ))
    }
}

// MARK: - ProjectCardDropIndicator

/// Leaf wrapper that subscribes to `dragState` so only this view re-renders
/// on drag updates.
struct ProjectCardDropIndicator: View {
    let project: Project
    let projectStore: ProjectStore
    let tabManager: SidebarTabManager
    let theme: SidebarTheme
    let depth: Int
    @ObservedObject var dragState: ProjectsDragState

    var body: some View {
        SidebarProjectCard(
            project: project,
            projectStore: projectStore,
            tabManager: tabManager,
            theme: theme,
            depth: depth
        )
        .sidebarDropIndicator(
            itemID: project.id,
            draggingID: dragState.draggingProjectUUID,
            dropTargetID: dragState.projectDropTarget?.projectID,
            edge: dragState.projectDropTarget?.edge ?? .top
        )
        .onDrag {
            dragState.beginProjectDrag(project.id)
            return SidebarDropPayload.project(project.id).itemProvider()
        }
        .onDrop(of: [.ghosttySidebarItem], delegate: ProjectDropDelegate(
            projectStore: projectStore,
            tabManager: tabManager,
            currentProject: project,
            dragState: dragState
        ))
    }
}

// MARK: - ProjectDropDelegate

private struct ProjectDropDelegate: DropDelegate {
    /// Approximate rendered height of a `SidebarProjectCard`. Used to map
    /// the drop cursor's Y position to a top/bottom insertion edge.
    private static let cardHeight: CGFloat = 40

    let projectStore: ProjectStore
    let tabManager: SidebarTabManager
    let currentProject: Project
    let dragState: ProjectsDragState

    private func edge(for info: DropInfo) -> DropEdge {
        info.location.y < Self.cardHeight / 2 ? .top : .bottom
    }

    func dropEntered(info: DropInfo) {
        guard dragState.isDragging else { return }
        dragState.setProjectDropTarget(ProjectDropTarget(projectID: currentProject.id, edge: edge(for: info)))
    }

    func dropExited(info: DropInfo) {
        if dragState.projectDropTarget?.projectID == currentProject.id {
            dragState.setProjectDropTarget(nil)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard dragState.isDragging else { return DropProposal(operation: .forbidden) }
        dragState.setProjectDropTarget(ProjectDropTarget(projectID: currentProject.id, edge: edge(for: info)))
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        switch dragState.draggingItem {
        case .project(let projectId):
            return projectId != currentProject.id
        case .folder, .tab, .none:
            // Accept any in-app sidebar drop (tab → project snapshot, etc.).
            return true
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        let insertEdge = edge(for: info)

        if case .project(let sourceId) = dragState.draggingItem {
            // Same-folder reorder and cross-folder move share this path:
            // moveProject is a no-op when source folder == target, then
            // insertProject reassigns sortOrders.
            projectStore.moveProject(sourceId, toFolder: currentProject.folderId)
            projectStore.insertProject(
                sourceId,
                relativeTo: currentProject.id,
                edge: insertEdge,
                inFolder: currentProject.folderId
            )
            dragState.reset()
            return true
        }

        let accepted = info.loadSidebarPayload { payload in
            switch payload {
            case .tab(let index):
                projectStore.snapshotTabIntoProject(
                    tabIndex: index,
                    tabManager: tabManager,
                    targetFolderId: currentProject.folderId,
                    insertRelativeTo: (currentProject.id, insertEdge)
                )
            case .project, .folder:
                break
            }
        }

        dragState.reset()
        return accepted
    }
}

// MARK: - Drag-Drop Indicators

extension View {
    /// Dims the dragged item and shows an insertion line at the top or
    /// bottom edge of the drop target. Pass `edge: .top` (the default) for
    /// items that don't distinguish leading/trailing drop positions.
    func sidebarDropIndicator(
        itemID: UUID,
        draggingID: UUID?,
        dropTargetID: UUID?,
        edge: DropEdge = .top
    ) -> some View {
        self
            .opacity(draggingID == itemID ? 0.4 : 1.0)
            .overlay(alignment: edge == .bottom ? .bottom : .top) {
                if dropTargetID == itemID && draggingID != itemID {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: edge == .bottom ? 1 : -1)
                }
            }
    }
}

// MARK: - FolderDropDelegate

private struct FolderDropDelegate: DropDelegate {
    let projectStore: ProjectStore
    let currentFolder: ProjectFolder
    let dragState: ProjectsDragState

    func dropEntered(info: DropInfo) {
        guard dragState.isDragging else { return }
        dragState.setDropTargetFolderID(currentFolder.id)
    }

    func dropExited(info: DropInfo) {
        if dragState.dropTargetFolderID == currentFolder.id {
            dragState.setDropTargetFolderID(nil)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard dragState.isDragging else { return DropProposal(operation: .forbidden) }
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        switch dragState.draggingItem {
        case .folder(let folderId):
            guard folderId != currentFolder.id else { return false }
            // Only allow reordering within the same parent — `reorderFolder`
            // operates on a single sibling list, so a cross-parent drop
            // would silently no-op. This implicitly rejects cycles too,
            // since a folder is never a sibling of its own descendants.
            let sourceParentId = projectStore.folders.first(where: { $0.id == folderId })?.parentId
            return sourceParentId == currentFolder.parentId
        case .project:
            return true
        case .tab, .none:
            return false
        }
    }

    func performDrop(info: DropInfo) -> Bool {
        switch dragState.draggingItem {
        case .folder(let sourceId):
            projectStore.reorderFolder(
                fromId: sourceId,
                toId: currentFolder.id,
                inParent: currentFolder.parentId
            )
            dragState.reset()
            return true
        case .project(let projectId):
            projectStore.moveProject(
                projectId,
                toFolder: currentFolder.id,
                atSortOrder: projectStore.nextSortOrder(in: currentFolder.id)
            )
            dragState.reset()
            return true
        case .tab, .none:
            return false
        }
    }
}
