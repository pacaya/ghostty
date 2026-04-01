import SwiftUI
import UniformTypeIdentifiers

/// A recursive folder row in the projects tree with disclosure triangle and children.
struct ProjectFolderRow: View {
    let folder: ProjectFolder
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme
    let depth: Int

    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""
    @FocusState private var isRenameFocused: Bool
    @Binding var draggingProjectID: UUID?
    @Binding var projectDropTarget: ProjectDropTarget?
    @Binding var draggingTabID: ObjectIdentifier?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Folder header
            HStack(spacing: 4) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(theme.secondaryText)
                    .rotationEffect(.degrees(folder.isExpanded ? 90 : 0))
                    .animation(.easeInOut(duration: 0.15), value: folder.isExpanded)

                Image(systemName: folder.isExpanded ? "folder.fill" : "folder")
                    .font(.system(size: 10))
                    .foregroundColor(theme.secondaryText)

                if isRenaming {
                    TextField("Folder name", text: $renameText, onCommit: {
                        if !renameText.isEmpty {
                            projectStore.renameFolder(folder.id, to: renameText)
                        }
                        isRenameFocused = false
                        isRenaming = false
                    })
                    .focused($isRenameFocused)
                    .textFieldStyle(.plain)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(theme.foreground)
                } else {
                    Text(folder.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(theme.foreground)
                        .lineLimit(1)
                }

                Spacer()
            }
            .padding(.leading, CGFloat(depth) * 12)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .contentShape(Rectangle())
            .onTapGesture {
                if draggingProjectID != nil { draggingProjectID = nil }
                if projectDropTarget != nil { projectDropTarget = nil }
                withAnimation(.easeInOut(duration: 0.15)) {
                    projectStore.toggleFolderExpansion(folder.id)
                }
            }
            .contextMenu {
                Button("Rename...") {
                    renameText = folder.name
                    isRenaming = true
                }

                Button("New Subfolder") {
                    let subfolder = ProjectFolder(
                        id: UUID(),
                        name: projectStore.uniqueFolderName(for: "New Folder", in: folder.id),
                        parentId: folder.id,
                        sortOrder: projectStore.nextSortOrder(in: folder.id)
                    )
                    projectStore.addFolder(subfolder)
                    if !folder.isExpanded {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            projectStore.setFolderExpanded(folder.id, true)
                        }
                    }
                }

                Divider()

                Button("Delete", role: .destructive) {
                    projectStore.deleteFolder(id: folder.id, recursive: true)
                }
            }
            .onDrop(of: [UTType.text], delegate: TabToProjectDropDelegate(
                projectStore: projectStore,
                tabManager: tabManager,
                targetFolderId: folder.id,
                draggingTabID: $draggingTabID
            ))
            .onChange(of: isRenaming) { renaming in
                if renaming {
                    isRenameFocused = true
                }
            }

            // Children (when expanded)
            if folder.isExpanded {
                // Child folders
                ForEach(projectStore.childFolders(of: folder.id)) { childFolder in
                    ProjectFolderRow(
                        folder: childFolder,
                        projectStore: projectStore,
                        tabManager: tabManager,
                        theme: theme,
                        depth: depth + 1,
                        draggingProjectID: $draggingProjectID,
                        projectDropTarget: $projectDropTarget,
                        draggingTabID: $draggingTabID
                    )
                }

                // Projects in this folder
                ForEach(projectStore.projects(in: folder.id)) { project in
                    SidebarProjectCard(
                        project: project,
                        projectStore: projectStore,
                        tabManager: tabManager,
                        theme: theme,
                        depth: depth + 1
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
        }
        .padding(.top, depth == 0 ? 6 : 2)
    }
}
