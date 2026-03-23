import SwiftUI
import UniformTypeIdentifiers

/// Scrollable tree view of project folders and project items.
struct ProjectsListView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme

    @State private var draggingProjectID: UUID?
    @State private var dropTargetProjectID: UUID?
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
                            depth: 0
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
                            draggingProjectID: $draggingProjectID,
                            dropTargetProjectID: $dropTargetProjectID
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
                        .dragDropIndicator(itemID: project.id, draggingID: draggingProjectID, dropTargetID: dropTargetProjectID)
                        .onDrag {
                            draggingProjectID = project.id
                            return NSItemProvider(object: "project:\(project.id.uuidString)" as NSString)
                        }
                        .onDrop(of: [UTType.text], delegate: ProjectDropDelegate(
                            projectStore: projectStore,
                            currentProject: project,
                            draggingProjectID: $draggingProjectID,
                            dropTargetProjectID: $dropTargetProjectID
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
    let projectStore: ProjectStore
    let currentProject: Project
    @Binding var draggingProjectID: UUID?
    @Binding var dropTargetProjectID: UUID?

    func dropEntered(info: DropInfo) {
        dropTargetProjectID = currentProject.id
    }

    func dropExited(info: DropInfo) {
        if dropTargetProjectID == currentProject.id {
            dropTargetProjectID = nil
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        draggingProjectID != nil && draggingProjectID != currentProject.id
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let sourceId = draggingProjectID else { return false }

        projectStore.reorderProject(
            fromId: sourceId,
            toId: currentProject.id,
            inFolder: currentProject.folderId
        )

        draggingProjectID = nil
        dropTargetProjectID = nil
        return true
    }
}

// MARK: - Drag-Drop Indicator

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
}

// MARK: - FolderDropDelegate

private struct FolderDropDelegate: DropDelegate {
    let projectStore: ProjectStore
    let currentFolder: ProjectFolder
    @Binding var draggingFolderID: UUID?
    @Binding var dropTargetFolderID: UUID?
    @Binding var draggingProjectID: UUID?
    @Binding var dropTargetProjectID: UUID?

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
            dropTargetProjectID = nil
            return true
        }

        return false
    }
}
