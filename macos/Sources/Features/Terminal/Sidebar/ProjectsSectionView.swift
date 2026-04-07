import SwiftUI
import UniformTypeIdentifiers

/// The projects section of the sidebar, containing a header bar and a scrollable project tree.
struct ProjectsSectionView: View {
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme
    @Binding var isExpanded: Bool
    @Binding var splitRatio: Double
    let totalHeight: CGFloat
    let headerHeight: CGFloat
    let dragState: ProjectsDragState

    var body: some View {
        VStack(spacing: 0) {
            // Resizable divider (only when expanded)
            if isExpanded {
                SidebarSplitDivider(
                    splitRatio: $splitRatio,
                    totalHeight: totalHeight
                )
            }

            // Header bar (always visible)
            ProjectsSectionHeader(
                isExpanded: $isExpanded,
                theme: theme,
                onNewFolder: createFolder,
                onImport: importProject
            )

            // Expanded content
            if isExpanded {
                ProjectsListView(
                    projectStore: projectStore,
                    tabManager: tabManager,
                    theme: theme,
                    dragState: dragState
                )
            }
        }
    }

    private func createFolder() {
        let folder = ProjectFolder(
            id: UUID(),
            name: projectStore.uniqueFolderName(for: "New Folder", in: nil),
            parentId: nil,
            sortOrder: projectStore.nextRootSortOrder()
        )
        projectStore.addFolder(folder)
    }

    private func importProject() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Select a Ghostty project file to import"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    let data = try Data(contentsOf: url)
                    _ = try projectStore.importProjects(from: data)
                } catch {
                    // Could show an alert here; for now just log
                    NSSound.beep()
                }
            }
        }
    }
}

// MARK: - Header

/// The thin header bar for the projects section with expand/collapse toggle.
struct ProjectsSectionHeader: View {
    @Binding var isExpanded: Bool
    var theme: SidebarTheme
    var onNewFolder: () -> Void
    var onImport: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "chevron.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(theme.secondaryText)
                .rotationEffect(.degrees(isExpanded ? 90 : 0))

            Text("Projects")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(theme.secondaryText)

            Spacer()

            if isExpanded {
                Button(action: onNewFolder) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 10))
                        .foregroundColor(theme.secondaryText)
                }
                .buttonStyle(.plain)
                .help("New Folder")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded.toggle()
            }
        }
        .contextMenu {
            if isExpanded {
                Button("Collapse") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = false
                    }
                }
            } else {
                Button("Expand") {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
            }

            Divider()

            Button("New Folder") {
                if !isExpanded {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isExpanded = true
                    }
                }
                onNewFolder()
            }

            Button("Import Project...") {
                onImport()
            }
        }
    }
}

// MARK: - Tab to Project Drop

/// Handles dropping a tab card from the tabs section into the projects section.
struct TabToProjectDropDelegate: DropDelegate {
    let projectStore: ProjectStore
    let tabManager: SidebarTabManager
    let targetFolderId: UUID?
    let dragState: ProjectsDragState

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.ghosttySidebarItem])
    }

    func performDrop(info: DropInfo) -> Bool {
        let accepted = info.loadSidebarPayload { payload in
            switch payload {
            case .project(let projectId):
                projectStore.moveProject(
                    projectId,
                    toFolder: targetFolderId,
                    atSortOrder: projectStore.nextSortOrder(in: targetFolderId)
                )
            case .tab(let index):
                projectStore.snapshotTabIntoProject(
                    tabIndex: index,
                    tabManager: tabManager,
                    targetFolderId: targetFolderId
                )
            case .folder:
                break
            }
        }

        dragState.reset()
        return accepted
    }
}
