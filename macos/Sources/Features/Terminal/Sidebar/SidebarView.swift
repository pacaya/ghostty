import SwiftUI
import UniformTypeIdentifiers

// MARK: - SidebarTheme

struct SidebarTheme: Equatable {
    let background: Color
    let foreground: Color
    let secondaryText: Color
    let activeTabBackground: Color
    let attentionColor: Color

    /// Create from Ghostty terminal colors.
    static func from(background: NSColor, foreground: NSColor) -> SidebarTheme {
        let bgLuminance = background.luminance
        let sidebarBg: Color
        if bgLuminance > 0.5 {
            // Light theme: darken sidebar slightly
            sidebarBg = Color(nsColor: background.darken(by: 0.05))
        } else {
            // Dark theme: lighten sidebar slightly
            sidebarBg = Color(nsColor: background.blended(withFraction: 0.08, of: NSColor.white) ?? background)
        }

        let fg = Color(nsColor: foreground)

        return SidebarTheme(
            background: sidebarBg,
            foreground: fg,
            secondaryText: fg.opacity(0.6),
            activeTabBackground: fg.opacity(0.12),
            attentionColor: .orange
        )
    }

    /// Sensible default when no terminal colors are available yet.
    static var `default`: SidebarTheme {
        SidebarTheme(
            background: Color(nsColor: .controlBackgroundColor),
            foreground: .primary,
            secondaryText: .secondary,
            activeTabBackground: Color.accentColor.opacity(0.12),
            attentionColor: .orange
        )
    }
}

// MARK: - SidebarField

enum SidebarField: String, Hashable {
    case title
    case directory
    case gitBranch = "git-branch"
    case status

    static let defaultFields: Set<SidebarField> = [.title, .directory, .gitBranch, .status]
}

// MARK: - SidebarView

/// A vertical sidebar that displays the list of tabs for the current window group.
struct SidebarView: View {
    @ObservedObject var tabManager: SidebarTabManager
    @ObservedObject var projectStore: ProjectStore
    var theme: SidebarTheme
    var fields: Set<SidebarField> = SidebarField.defaultFields

    @AppStorage("SidebarShowCardBorder") private var showCardBorder: Bool = true
    @AppStorage("SidebarDimInactiveColors") private var dimInactiveColors: Bool = false
    @ObservedObject var dragState: ProjectsDragState

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 4) {
                ForEach(Array(tabManager.tabs.enumerated()), id: \.element.id) { index, tab in
                    tabRow(tab, index: index)
                }
            }
            .padding(.horizontal, 8)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.background)
    }

    @ViewBuilder
    private func tabRow(_ tab: SidebarTabManager.TabItem, index: Int) -> some View {
        SidebarTabCard(tab: tab, theme: theme, fields: fields, projectStore: projectStore, tabManager: tabManager, dragState: dragState, showCardBorder: showCardBorder, dimInactive: dimInactiveColors)
            .contentShape(Rectangle())
            .opacity(dragState.draggingItem == .tab(tab.id) ? 0.4 : 1.0)
            .overlay(alignment: .top) {
                if dragState.dropTargetTabID == tab.id && dragState.draggingItem != .tab(tab.id) {
                    Rectangle()
                        .fill(Color.accentColor)
                        .frame(height: 2)
                        .offset(y: -3)
                }
            }
            .onTapGesture {
                dragState.reset()
                tabManager.selectTab(tab)
            }
            .onDrag {
                dragState.beginTabDrag(tab.id)
                return SidebarDropPayload.tab(index).itemProvider()
            }
            .onDrop(of: [.ghosttySidebarItem], delegate: TabDropDelegate(
                tabManager: tabManager,
                currentTab: tab,
                currentIndex: index,
                dragState: dragState
            ))
            .contextMenu {
                Button("Rename Tab...") {
                    tabManager.promptRenameTab(tab)
                }

                Divider()

                Menu("Tab Color") {
                    ForEach(TerminalTabColor.allCases, id: \.self) { color in
                        Button {
                            tabManager.setTabColor(color, for: tab)
                        } label: {
                            Label {
                                Text(color.localizedName)
                            } icon: {
                                Image(nsImage: color.swatchImage(selected: color == tab.tabColor))
                            }
                        }
                    }
                }

                Toggle("Show Tab Border", isOn: $showCardBorder)
                Toggle("Dim Inactive Tab Colors", isOn: $dimInactiveColors)

                Divider()

                if projectStore.projectId(for: tab.window) != nil {
                    Button("Close Tab") {
                        closeTab(tab)
                    }
                } else {
                    Button("Save to Projects") {
                        if let controller = tab.window.windowController as? BaseTerminalController,
                           let project = projectStore.snapshotFromTab(controller: controller) {
                            projectStore.associate(window: tab.window, with: project.id)
                        }
                    }
                }

                Button("Delete Tab") {
                    if projectStore.projectId(for: tab.window) != nil {
                        projectStore.disassociate(window: tab.window)
                    }
                    tabManager.closeTab(tab)
                }

                Button("Close Other Tabs") {
                    tabManager.closeOtherTabs(tab)
                }
                .disabled(tabManager.tabs.count <= 1)

                Button("Close Tabs to the Right") {
                    tabManager.closeTabsToTheRight(of: tab)
                }
                .disabled({
                    guard let idx = tabManager.tabs.firstIndex(where: { $0.id == tab.id }) else { return true }
                    return idx >= tabManager.tabs.count - 1
                }())
            }
    }

    private func closeTab(_ tab: SidebarTabManager.TabItem) {
        if let projectId = projectStore.projectId(for: tab.window) {
            if let controller = tab.window.windowController as? BaseTerminalController {
                _ = projectStore.snapshotFromTab(
                    controller: controller,
                    existingProjectId: projectId
                )
            }
            projectStore.disassociate(window: tab.window)
        }
        tabManager.closeTab(tab)
    }
}

// MARK: - TabDropDelegate

private struct TabDropDelegate: DropDelegate {
    let tabManager: SidebarTabManager
    let currentTab: SidebarTabManager.TabItem
    let currentIndex: Int
    let dragState: ProjectsDragState

    func dropEntered(info: DropInfo) {
        guard dragState.isDragging else { return }
        dragState.setDropTargetTabID(currentTab.id)
    }

    func dropExited(info: DropInfo) {
        if dragState.dropTargetTabID == currentTab.id {
            dragState.setDropTargetTabID(nil)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard dragState.isDragging else { return DropProposal(operation: .forbidden) }
        dragState.setDropTargetTabID(currentTab.id)
        return DropProposal(operation: .move)
    }

    func validateDrop(info: DropInfo) -> Bool {
        guard case .tab(let draggingTabID) = dragState.draggingItem else { return false }
        return draggingTabID != currentTab.id
    }

    func performDrop(info: DropInfo) -> Bool {
        guard case .tab(let draggingTabID) = dragState.draggingItem else { return false }
        guard let sourceIndex = tabManager.tabs.firstIndex(where: { $0.id == draggingTabID }) else { return false }

        tabManager.moveTab(from: sourceIndex, to: currentIndex)
        dragState.reset()
        return true
    }
}

// MARK: - SidebarTabCard

private struct SidebarTabCard: View {
    let tab: SidebarTabManager.TabItem
    let theme: SidebarTheme
    let fields: Set<SidebarField>
    @ObservedObject var projectStore: ProjectStore
    let tabManager: SidebarTabManager
    let dragState: ProjectsDragState
    var showCardBorder: Bool = true
    var dimInactive: Bool = false

    @State private var isHovered: Bool = false

    private static let cardRadius: CGFloat = 8

    /// The accent color for the left border strip.
    /// When dimming is enabled, inactive tabs use reduced opacity for a gentle dim.
    /// When no color is set (.none), the strip is fully transparent.
    private var accentColor: Color {
        if let nsColor = tab.tabColor.displayColor {
            let base = Color(nsColor: nsColor)
            return (dimInactive && !tab.isSelected) ? base.opacity(0.55) : base
        }
        return .clear
    }

    /// The border color for the thin card border — always neutral gray.
    private var cardBorderColor: Color {
        Color(nsColor: .separatorColor).opacity(0.3)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left color accent strip — uses UnevenRoundedRectangle so it
            // follows the card's left-side rounding while staying flat on the right.
            UnevenRoundedRectangle(
                topLeadingRadius: Self.cardRadius,
                bottomLeadingRadius: Self.cardRadius,
                bottomTrailingRadius: 0,
                topTrailingRadius: 0
            )
            .fill(accentColor)
            .frame(width: 5)

            VStack(alignment: .leading, spacing: 4) {
                // Title (always shown — attention dot lives here)
                if fields.contains(.title) {
                    HStack(spacing: 6) {
                        Text(tab.displayTitle)
                            .font(.system(size: 12, weight: tab.isSelected ? .semibold : .regular))
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .foregroundColor(tab.isSelected ? theme.foreground : theme.secondaryText)

                        Spacer()

                        if isHovered && dragState.draggingItem == nil {
                            let isSaved = projectStore.projectId(for: tab.window) != nil
                            Button(action: closeTab) {
                                Image(systemName: isSaved ? "xmark" : "trash")
                                    .font(.system(size: 9, weight: .medium))
                                    .foregroundColor(theme.secondaryText)
                            }
                            .buttonStyle(.plain)
                            .help(isSaved ? "Close Tab" : "Delete Tab")
                        } else {
                            if projectStore.projectId(for: tab.window) == nil {
                                Image(systemName: "circle.dashed")
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.secondaryText.opacity(0.5))
                            }

                            if tab.hasRunningProcess {
                                Image(systemName: "terminal")
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.attentionColor)
                            }

                            if tab.needsAttention {
                                Circle()
                                    .fill(theme.attentionColor)
                                    .frame(width: 8, height: 8)
                            }
                        }
                    }
                }

                // Directory name
                if fields.contains(.directory), let dir = tab.directoryName {
                    HStack(spacing: 4) {
                        Image(systemName: "folder")
                            .font(.system(size: 9))
                            .foregroundColor(theme.secondaryText)
                        Text(dir)
                            .font(.system(size: 10))
                            .foregroundColor(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                // Git branch
                if fields.contains(.gitBranch), let branch = tab.gitBranch {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                            .foregroundColor(theme.secondaryText)
                        Text(branch)
                            .font(.system(size: 10))
                            .foregroundColor(theme.secondaryText)
                            .lineLimit(1)
                    }
                }

                // Status entries
                if fields.contains(.status), !tab.statusEntries.isEmpty {
                    ForEach(tab.statusEntries, id: \.key) { entry in
                        HStack(spacing: 4) {
                            if let icon = entry.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 9))
                                    .foregroundColor(theme.secondaryText)
                            }
                            Text(entry.value)
                                .font(.system(size: 10))
                                .foregroundColor(theme.secondaryText)
                                .lineLimit(1)
                        }
                    }
                }
            }
            .padding(.vertical, 8)
            .padding(.leading, 8)
            .padding(.trailing, 10)
        }
        .clipShape(RoundedRectangle(cornerRadius: Self.cardRadius))
        .background(
            RoundedRectangle(cornerRadius: Self.cardRadius)
                .fill(tab.isSelected ? theme.activeTabBackground : Color.clear)
        )
        .overlay(
            Group {
                if showCardBorder {
                    RoundedRectangle(cornerRadius: Self.cardRadius)
                        .strokeBorder(cardBorderColor, lineWidth: 1)
                }
            }
        )
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeInOut(duration: 0.15), value: isHovered)
    }

    private func closeTab() {
        if let projectId = projectStore.projectId(for: tab.window) {
            if let controller = tab.window.windowController as? BaseTerminalController {
                _ = projectStore.snapshotFromTab(
                    controller: controller,
                    existingProjectId: projectId
                )
            }
            projectStore.disassociate(window: tab.window)
        }
        tabManager.closeTab(tab)
    }
}
