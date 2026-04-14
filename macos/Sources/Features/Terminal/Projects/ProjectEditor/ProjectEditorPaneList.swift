import SwiftUI

/// A flat DFS-ordered list of the panes in the edited layout. Selection is
/// two-way bound to `ProjectEditorModel.selection` so clicking a row here
/// stays in sync with the mini-map and the inspector on the right.
struct ProjectEditorPaneList: View {
    @ObservedObject var model: ProjectEditorModel

    var body: some View {
        let leaves = model.flatLeaves
        List(selection: $model.selection) {
            ForEach(Array(leaves.enumerated()), id: \.element.leaf.id) { i, entry in
                row(index: i, leaf: entry.leaf)
                    .tag(entry.indexPath)
            }
        }
    }

    @ViewBuilder
    private func row(index: Int, leaf: ProjectLayoutNode.ProjectLeaf) -> some View {
        HStack(spacing: 4) {
            Text("Pane \(index + 1)")
            Text("— \(label(for: leaf))")
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }

    private func label(for leaf: ProjectLayoutNode.ProjectLeaf) -> String {
        switch leaf.kind {
        case .browser:
            if let url = leaf.url, !url.isEmpty, let host = URL(string: url)?.host, !host.isEmpty {
                return host
            }
            return "Browser"
        case .terminal:
            let wd = leaf.workingDirectory
            guard !wd.isEmpty else { return "—" }
            let basename = URL(fileURLWithPath: wd).lastPathComponent
            return basename.isEmpty ? "—" : basename
        }
    }
}
