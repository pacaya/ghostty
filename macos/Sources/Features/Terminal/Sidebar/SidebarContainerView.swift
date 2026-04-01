import SwiftUI

/// Top-level sidebar view that wraps the tabs section (top) and projects section (bottom)
/// with a resizable divider between them.
struct SidebarContainerView: View {
    @ObservedObject var tabManager: SidebarTabManager
    @ObservedObject var projectStore: ProjectStore
    var theme: SidebarTheme
    var fields: Set<SidebarField>

    @AppStorage("SidebarProjectsExpanded") private var projectsExpanded: Bool = false
    @AppStorage("SidebarProjectsSplitRatio") private var splitRatio: Double = 0.5
    @State private var draggingTabID: ObjectIdentifier?

    /// Height of the collapsed projects header bar.
    private let headerHeight: CGFloat = 28

    var body: some View {
        GeometryReader { geo in
            let totalHeight = geo.size.height

            VStack(spacing: 0) {
                // Tabs section (top)
                SidebarView(
                    tabManager: tabManager,
                    projectStore: projectStore,
                    theme: theme,
                    fields: fields,
                    draggingTabID: $draggingTabID
                )
                .frame(height: tabsHeight(total: totalHeight))

                // Projects section (bottom)
                ProjectsSectionView(
                    projectStore: projectStore,
                    tabManager: tabManager,
                    theme: theme,
                    isExpanded: $projectsExpanded,
                    splitRatio: $splitRatio,
                    totalHeight: totalHeight,
                    headerHeight: headerHeight,
                    draggingTabID: $draggingTabID
                )
                .frame(height: projectsHeight(total: totalHeight))
            }
        }
        .background(theme.background)
    }

    private func tabsHeight(total: CGFloat) -> CGFloat {
        if projectsExpanded {
            return max(60, total * splitRatio)
        } else {
            return total - headerHeight
        }
    }

    private func projectsHeight(total: CGFloat) -> CGFloat {
        if projectsExpanded {
            return max(headerHeight, total * (1 - splitRatio))
        } else {
            return headerHeight
        }
    }
}
