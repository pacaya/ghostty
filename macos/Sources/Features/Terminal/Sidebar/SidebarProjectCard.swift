import SwiftUI

/// A project card in the sidebar, visually similar to `SidebarTabCard`.
struct SidebarProjectCard: View {
    let project: Project
    @ObservedObject var projectStore: ProjectStore
    @ObservedObject var tabManager: SidebarTabManager
    var theme: SidebarTheme
    let depth: Int

    @AppStorage("SidebarShowCardBorder") private var showCardBorder: Bool = true

    @State private var isRenaming: Bool = false
    @State private var renameText: String = ""
    @FocusState private var isRenameFocused: Bool
    @State private var isEditing = false

    private static let cardRadius: CGFloat = 8

    private func accentColor(isOpen: Bool) -> Color {
        if let nsColor = project.color.displayColor {
            let base = Color(nsColor: nsColor)
            return isOpen ? base : base.opacity(0.55)
        }
        return .clear
    }

    private var cardBorderColor: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }

    var body: some View {
        let isOpen = projectStore.isOpen(project.id)
        let isSelected: Bool = {
            guard let selectedTab = tabManager.tabs.first(where: { $0.isSelected }),
                  projectStore.projectId(for: selectedTab.window) == project.id else { return false }
            return true
        }()
        let cardTextColor = isOpen ? theme.secondaryText : theme.secondaryText.opacity(0.7)

        HStack(spacing: 0) {
            // Left color accent strip
            UnevenRoundedRectangle(
                topLeadingRadius: Self.cardRadius,
                bottomLeadingRadius: Self.cardRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(accentColor(isOpen: isOpen))
            .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if isRenaming {
                        TextField("Project name", text: $renameText, onCommit: {
                            if !renameText.isEmpty {
                                projectStore.renameProject(project.id, to: renameText)
                            }
                            isRenameFocused = false
                            isRenaming = false
                        })
                        .focused($isRenameFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(theme.foreground)
                    } else {
                        Text(project.name)
                            .font(.system(size: 12, weight: .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(cardTextColor)
                    }

                    Spacer()

                    if isOpen {
                        Circle()
                            .fill(theme.secondaryText)
                            .frame(width: 6, height: 6)
                    }
                }

                let paneCount = project.layoutRoot.leafCount
                if paneCount > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.split.2x1")
                            .font(.system(size: 9))
                            .foregroundColor(cardTextColor)
                        Text("\(paneCount) panes")
                            .font(.system(size: 10))
                            .foregroundColor(cardTextColor)
                            .lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 8)
            .padding(.trailing, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius))
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius)
                .fill(isSelected ? theme.activeTabBackground : Color.clear)
        )
        .overlay {
            if showCardBorder {
                RoundedRectangle(cornerRadius: Self.cardRadius)
                    .strokeBorder(cardBorderColor, lineWidth: 1)
            }
        }
        .padding(.leading, CGFloat(depth) * 12)
        .contentShape(Rectangle())
        .onTapGesture {
            openProject()
        }
        .contextMenu {
            Button("Open") {
                openProject()
            }

            Button("Rename...") {
                renameText = project.name
                isRenaming = true
            }

            Button("Edit...") { isEditing = true }

            Button("Duplicate") {
                _ = projectStore.duplicateProject(project)
            }

            Divider()

            Button("Export...") {
                exportProject()
            }

            Divider()

            Button("Delete", role: .destructive) {
                projectStore.deleteProject(id: project.id)
            }
        }
        .sheet(isPresented: $isEditing) {
            ProjectEditorSheet(project: project, projectStore: projectStore)
        }
        .onChange(of: isRenaming) { renaming in
            if renaming {
                isRenameFocused = true
            }
        }
    }

    // MARK: - Actions

    private func openProject() {
        // If already open, activate the associated tab
        if let window = projectStore.window(for: project.id) {
            window.makeKeyAndOrderFront(nil)
            return
        }

        // Create a new tab from the project layout
        guard let appDelegate = NSApp.delegate as? AppDelegate,
              let app = appDelegate.ghostty.app else { return }

        let tree = project.layoutRoot.buildSplitTree(app: app)
        let controller = TerminalController(appDelegate.ghostty, withSurfaceTree: tree)

        // Restore color and title
        if let window = controller.window as? TerminalWindow {
            window.tabColor = project.color
        }
        controller.titleOverride = project.name

        // Add as tab to current window group
        if let parentWindow = tabManager.tabs.first?.window {
            parentWindow.addTabbedWindow(controller.window!, ordered: .above)
        }

        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)

        // Register association
        if let window = controller.window {
            projectStore.associate(window: window, with: project.id)
        }
    }

    private func exportProject() {
        guard let data = projectStore.exportProjects([project.id]) else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(project.name).json"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

}
