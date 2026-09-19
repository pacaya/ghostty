import AppKit
import SwiftUI

/// Right-hand inspector form for the currently selected pane in the
/// project editor: working directory / command / initial input / env vars.
struct ProjectEditorInspector: View {
    @ObservedObject var model: ProjectEditorModel

    var body: some View {
        if let path = model.selection,
           model.leaf(at: path) != nil,
           let index = flatIndex(of: path) {
            Form {
                Section(header: Text("Pane \(index + 1)")) {
                    terminalFields(path: path)
                }
            }
            .formStyle(.grouped)
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        VStack {
            Spacer()
            Text("Select a pane")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Terminal fields

    @ViewBuilder
    private func terminalFields(path: IndexPath) -> some View {
        let wd = stringBinding(
            path: path,
            get: { $0.workingDirectory },
            set: { $0.workingDirectory = $1 }
        )
        let command = stringBinding(
            path: path,
            get: { $0.initialInput ?? "" },
            set: { $0.initialInput = $1.isEmpty ? nil : $1 }
        )
        let env = envBinding(path: path)

        LabeledContent("Working Directory") {
            HStack(spacing: 6) {
                TextField("", text: wd)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") { chooseWorkingDirectory(path: path) }
            }
        }

        VStack(alignment: .leading, spacing: 4) {
            LabeledContent("Command") {
                HStack {
                    TextField("", text: command, axis: .vertical)
                        .lineLimit(1...)
                        .textFieldStyle(.roundedBorder)
                }
            }
            Text("Runs after the shell loads. A trailing newline is added if missing.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        LabeledContent("Environment") {
            // Re-init per-path so the editor's internal row ordering doesn't
            // leak across pane selections.
            EnvironmentVariablesEditor(env: env)
                .id(path)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Helpers

    private func flatIndex(of path: IndexPath) -> Int? {
        model.flatLeaves.firstIndex(where: { $0.indexPath == path })
    }

    private func stringBinding(
        path: IndexPath,
        get: @escaping (ProjectLayoutNode.ProjectLeaf) -> String,
        set: @escaping (inout ProjectLayoutNode.ProjectLeaf, String) -> Void
    ) -> Binding<String> {
        Binding(
            get: { model.leaf(at: path).map(get) ?? "" },
            set: { newValue in
                model.updateLeaf(at: path) { set(&$0, newValue) }
            }
        )
    }

    private func envBinding(path: IndexPath) -> Binding<[String: String]> {
        Binding(
            get: { model.leaf(at: path)?.environmentVariables ?? [:] },
            set: { newValue in
                model.updateLeaf(at: path) { $0.environmentVariables = newValue }
            }
        )
    }

    private func chooseWorkingDirectory(path: IndexPath) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            model.updateLeaf(at: path) { $0.workingDirectory = url.path }
        }
    }
}
