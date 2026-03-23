import SwiftUI

/// A horizontal divider between the tabs and projects sections of the sidebar.
/// Follows the visual pattern from `SplitView.Divider`.
struct SidebarSplitDivider: View {
    @Binding var splitRatio: Double
    let totalHeight: CGFloat

    private let visibleSize: CGFloat = 1
    private let invisibleSize: CGFloat = 6

    var body: some View {
        ZStack {
            Color.clear
                .frame(height: visibleSize + invisibleSize)
                .contentShape(Rectangle())
            Rectangle()
                .fill(Color(nsColor: .separatorColor).opacity(0.5))
                .frame(height: visibleSize)
        }
        .backport.pointerStyle(.resizeUpDown)
        .onHover { isHovered in
            if #available(macOS 15, *) { return }
            if isHovered {
                NSCursor.resizeUpDown.push()
            } else {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture()
                .onChanged { value in
                    guard totalHeight > 0 else { return }
                    let newRatio = value.location.y / totalHeight + splitRatio
                    splitRatio = min(max(newRatio, 0.15), 0.85)
                }
        )
        .onTapGesture(count: 2) {
            splitRatio = 0.5
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Sidebar section divider")
        .accessibilityValue("\(Int(splitRatio * 100))% tabs, \(Int((1 - splitRatio) * 100))% projects")
        .accessibilityHint("Drag to resize the tabs and projects sections")
        .accessibilityAddTraits(.isButton)
        .accessibilityAdjustableAction { direction in
            let adjustment: CGFloat = 0.025
            switch direction {
            case .increment:
                splitRatio = min(splitRatio + adjustment, 0.85)
            case .decrement:
                splitRatio = max(splitRatio - adjustment, 0.15)
            @unknown default:
                break
            }
        }
    }
}
