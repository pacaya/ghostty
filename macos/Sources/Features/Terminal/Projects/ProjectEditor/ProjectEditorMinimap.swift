import SwiftUI

/// A schematic preview of the project's split tree. Renders each leaf as a
/// tappable rounded rectangle labelled with its 1-indexed DFS pane number,
/// and highlights the currently selected leaf.
struct ProjectEditorMinimap: View {
    @ObservedObject var model: ProjectEditorModel

    private static let tileCornerRadius: CGFloat = 6
    private static let tileGap: CGFloat = 2

    var body: some View {
        // Compute the path→pane-number map once per render so the recursion
        // doesn't call `flatLeaves` O(n) times (that property re-walks the
        // whole tree on each access).
        let numbering: [IndexPath: Int] = Dictionary(
            uniqueKeysWithValues: model.flatLeaves.enumerated().map { ($0.element.indexPath, $0.offset + 1) }
        )
        GeometryReader { geometry in
            render(
                node: model.editedLayout,
                path: IndexPath(),
                size: geometry.size,
                numbering: numbering
            )
        }
    }

    // AnyView at the recursion boundary: Swift can't resolve a recursive
    // opaque `some View` return type.
    private func render(
        node: ProjectLayoutNode,
        path: IndexPath,
        size: CGSize,
        numbering: [IndexPath: Int]
    ) -> AnyView {
        switch node {
        case .leaf:
            return AnyView(leafTile(path: path, number: numbering[path]))
        case .split(let split):
            return AnyView(splitTiles(split: split, path: path, size: size, numbering: numbering))
        }
    }

    @ViewBuilder
    private func leafTile(path: IndexPath, number: Int?) -> some View {
        let isSelected = model.selection == path
        let fill: Color = isSelected
            ? Color.accentColor.opacity(0.85)
            : Color.secondary.opacity(0.25)
        let stroke: Color = isSelected
            ? Color.accentColor
            : Color.secondary.opacity(0.5)
        let textColor: Color = isSelected ? Color.white : Color.primary

        ZStack {
            RoundedRectangle(cornerRadius: Self.tileCornerRadius)
                .fill(fill)
            RoundedRectangle(cornerRadius: Self.tileCornerRadius)
                .strokeBorder(stroke, lineWidth: isSelected ? 2 : 1)
            if let number {
                Text("\(number)")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundColor(textColor)
            }
        }
        .padding(Self.tileGap)
        .contentShape(Rectangle())
        .onTapGesture {
            model.selection = path
        }
    }

    @ViewBuilder
    private func splitTiles(
        split: ProjectLayoutNode.ProjectSplit,
        path: IndexPath,
        size: CGSize,
        numbering: [IndexPath: Int]
    ) -> some View {
        let ratio = CGFloat(max(0.0, min(1.0, split.ratio)))
        let (leftSize, rightSize) = childSizes(size: size, ratio: ratio, direction: split.direction)
        let left = render(node: split.left, path: path.appending(0), size: leftSize, numbering: numbering)
        let right = render(node: split.right, path: path.appending(1), size: rightSize, numbering: numbering)

        switch split.direction {
        case .horizontal:
            HStack(spacing: 0) {
                left.frame(width: leftSize.width)
                right.frame(width: rightSize.width)
            }
        case .vertical:
            VStack(spacing: 0) {
                left.frame(height: leftSize.height)
                right.frame(height: rightSize.height)
            }
        }
    }

    private func childSizes(
        size: CGSize,
        ratio: CGFloat,
        direction: ProjectSplitDirection
    ) -> (CGSize, CGSize) {
        switch direction {
        case .horizontal:
            return (
                CGSize(width: size.width * ratio, height: size.height),
                CGSize(width: size.width * (1 - ratio), height: size.height)
            )
        case .vertical:
            return (
                CGSize(width: size.width, height: size.height * ratio),
                CGSize(width: size.width, height: size.height * (1 - ratio))
            )
        }
    }
}
