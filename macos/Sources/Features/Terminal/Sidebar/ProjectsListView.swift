import SwiftUI
import UniformTypeIdentifiers

// MARK: - Drop Position Types

enum DropEdge: Equatable {
    case top
    case bottom
}

struct ProjectDropTarget: Equatable {
    let projectID: UUID
    let edge: DropEdge
}

/// Scrollable tree view of project folders and project items.
struct ProjectsListView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme
    @Binding var draggingTabID: ObjectIdentifier?

    @State private var draggingProjectID: UUID?
    @State private var projectDropTarget: ProjectDropTarget?
    @State private var draggingFolderID: UUID?
    @State private var dropTargetFolderID: UUID?

    var body: some View {
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
                        ProjectFolderRow(
                            folder: folder,
                            projectStore: projectStore,
                            tabManager: tabManager,
                            theme: theme,
                            depth: 0,
                            draggingProjectID: $draggingProjectID,
                            projectDropTarget: $projectDropTarget,
                            draggingTabID: $draggingTabID
                        )
                        .dragDropIndicator(itemID: folder.id, draggingID: draggingFolderID, dropTargetID: dropTargetFolderID)
                        .onDrag {
                            draggingFolderID = folder.id
                            return NSItemProvider(object: "folder:\(folder.id.uuidString)" as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: FolderDropDelegate(
                            projectStore: projectStore,
                            currentFolder: folder,
                            draggingFolderID: $draggingFolderID,
                            dropTargetFolderID: $dropTargetFolderID,
                            draggingProjectID: $draggingProjectID
                        ))
                    }

                    // Root-level projects
                    ForEach(projectStore.rootProjects()) { project in
                        SidebarProjectCard(
                            project: project,
                            projectStore: projectStore,
                            tabManager: tabManager,
                            theme: theme,
                            depth: 0
                        )
                        .projectDragDropIndicator(itemID: project.id, draggingID: draggingProjectID, dropTarget: projectDropTarget)
                        .onDrag {
                            draggingProjectID = project.id
                            return NSItemProvider(object: "project:\(project.id.uuidString)" as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ProjectDropDelegate(
                            projectStore: projectStore,
                            tabManager: tabManager,
                            currentProject: project,
                            draggingProjectID: $draggingProjectID,
                            projectDropTarget: $projectDropTarget
                        ))
                    }
                }
                .padding(.horizontal, 8)
                .padding(.top, 4)
            }
        }
    }
}

// MARK: - ProjectDropDelegate

struct ProjectDropDelegate: DropDelegate {
    static let defaultCardHeight: CGFloat = 40

    let projectStore: ProjectStore
    let tabManager: SidebarTabManager
    let currentProject: Project
    var cardHeight: CGFloat = Self.defaultCardHeight
    @Binding var draggingProjectID: UUID?
    @Binding var projectDropTarget: ProjectDropTarget?

    private func edge(for info: DropInfo) -> DropEdge {
        info.location.y < cardHeight / 2 ? .top : .bottom
    }

    func dropEntered(info: DropInfo) {
        projectDropTarget = ProjectDropTarget(projectID: currentProject.id, edge: edge(for: info))
    }

    func dropExited(info: DropInfo) {
        if projectDropTarget?.projectID == currentProject.id {
            projectDropTarget = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        let newTarget = ProjectDropTarget(projectID: currentProject.id, edge: edge(for: info))
        if projectDropTarget != newTarget {
            projectDropTarget = newTarget
        }
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Accept project reorder
        if let projectId = draggingProjectID {
            return projectId != currentProject.id
        }
        // Accept tab drops
        return info.hasItemsConforming(to: [UTType.text])
    }

    func performDrop(info: DropInfo) -> Bool {
        let insertEdge = edge(for: info)

        // Case 1: Project-to-project reorder
        if let sourceId = draggingProjectID {
            projectStore.reorderProject(
                fromId: sourceId,
                toId: currentProject.id,
                inFolder: currentProject.folderId
            )
            draggingProjectID = nil
            projectDropTarget = nil
            return true
        }

        // Case 2: Tab or project drop from payload
        guard let item = info.itemProviders(for: [UTType.text]).first else {
            projectDropTarget = nil
            return false
        }

        item.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { data, _ in
            guard let data = data as? Data,
                  let payload = String(data: data, encoding: .utf8) else { return }

            Task { @MainActor in
                if payload.hasPrefix("project:"),
                   let projectId = UUID(uuidString: String(payload.dropFirst("project:".count))) {
                    // Move existing project to this position
                    projectStore.moveProject(projectId, toFolder: currentProject.folderId)
                    projectStore.insertProject(projectId, relativeTo: currentProject.id, edge: insertEdge, inFolder: currentProject.folderId)
                } else if let index = Int(payload) {
                    // Tab drop: snapshot and insert at position
                    guard index >= 0, index < tabManager.tabs.count else { return }
                    let tab = tabManager.tabs[index]
                    guard let controller = tab.window.windowController as? BaseTerminalController else { return }

                    if let project = projectStore.snapshotFromTab(controller: controller) {
                        var updated = project
                        updated.folderId = currentProject.folderId
                        projectStore.updateProject(updated)
                        projectStore.insertProject(project.id, relativeTo: currentProject.id, edge: insertEdge, inFolder: currentProject.folderId)
                        projectStore.associate(window: tab.window, with: project.id)
                    }
                }
            }
        }

        projectDropTarget = nil
        return true
    }
}

// MARK: - Drag-Drop Indicators

extension View {
    /// Applies the standard drag-drop visual treatment: dims the dragged item
    /// and shows a colored line above the current drop target.
    func dragDropIndicator(
        itemID: UUID,
        draggingID: UUID?,
        dropTargetID: UUID?
    ) -> some View {
        self
            .opacity(draggingID == itemID ? 0.4 : 1.0)
            .overlay(alignment: .top) {
                if dropTargetID == itemID && draggingID != itemID {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: -1)
                }
            }
    }

    /// Position-aware drag-drop indicator that shows the insertion line at the
    /// top or bottom edge depending on cursor position.
    func projectDragDropIndicator(
        itemID: UUID,
        draggingID: UUID?,
        dropTarget: ProjectDropTarget?
    ) -> some View {
        self
            .opacity(draggingID == itemID ? 0.4 : 1.0)
            .overlay(alignment: dropTarget?.edge == .bottom ? .bottom : .top) {
                if dropTarget?.projectID == itemID && draggingID != itemID {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: dropTarget?.edge == .bottom ? 1 : -1)
                }
            }
    }
}

// MARK: - FolderDropDelegate

private struct FolderDropDelegate: DropDelegate {
    let projectStore: ProjectStore
    let currentFolder: ProjectFolder
    @Binding var draggingFolderID: UUID?
    @Binding var dropTargetFolderID: UUID?
    @Binding var draggingProjectID: UUID?

    func dropEntered(info: DropInfo) {
        dropTargetFolderID = currentFolder.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetFolderID == currentFolder.id {
            dropTargetFolderID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        // Accept folder reorder or project-into-folder drop
        if let folderId = draggingFolderID {
            return folderId != currentFolder.id
        }
        return draggingProjectID != nil
    }

    func performDrop(info: DropInfo) -> Bool {
        if let sourceId = draggingFolderID {
            projectStore.reorderFolder(
                fromId: sourceId,
                toId: currentFolder.id,
                inParent: currentFolder.parentId
            )
            draggingFolderID = nil
            dropTargetFolderID = nil
            return true
        }

        if let projectId = draggingProjectID {
            projectStore.moveProject(
                projectId,
                toFolder: currentFolder.id,
                atSortOrder: projectStore.nextSortOrder(in: currentFolder.id)
            )
            draggingProjectID = nil
            return true
        }

        return false
    }
}
