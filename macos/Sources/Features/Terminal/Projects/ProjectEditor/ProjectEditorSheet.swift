import SwiftUI

/// Top-level sheet for editing a project's layout and per-pane settings.
/// Left pane shows a minimap preview over a DFS list of panes; right pane
/// is the inspector for the selected leaf. Save commits through the store.
struct ProjectEditorSheet: View {
    @StateObject private var model: ProjectEditorModel
    private let projectStore: ProjectStore
    private let projectName: String

    @Environment(\.dismiss) private var dismiss

    init(project: Project, projectStore: ProjectStore) {
        _model = StateObject(wrappedValue: ProjectEditorModel(project: project))
        self.projectStore = projectStore
        self.projectName = project.name
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(projectName)
                    .font(.headline)
                Spacer()
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            HSplitView {
                VStack(spacing: 0) {
                    ProjectEditorMinimap(model: model)
                        .aspectRatio(16.0 / 10.0, contentMode: .fit)
                        .padding()
                    Divider()
                    ProjectEditorPaneList(model: model)
                }
                .frame(minWidth: 260)

                ProjectEditorInspector(model: model)
                    .frame(minWidth: 320)
            }

            Divider()

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    model.save(to: projectStore)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(minWidth: 720, minHeight: 460)
    }
}
