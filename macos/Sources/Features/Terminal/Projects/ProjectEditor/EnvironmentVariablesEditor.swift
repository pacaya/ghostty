import SwiftUI

/// A reusable key/value list editor for environment variables.
///
/// Two-way bound to a `[String: String]`. Internally tracks an ordered
/// array of rows to preserve insertion order while editing (dictionaries
/// are unordered). On every mutation the internal rows are flushed back
/// to the bound dictionary, filtering out empty keys. Duplicate keys are
/// allowed during editing — last write wins when flushing to the dict.
struct EnvironmentVariablesEditor: View {
    @Binding var env: [String: String]

    @State private var rows: [Row] = []

    private struct Row: Identifiable {
        let id = UUID()
        var key: String
        var value: String
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if rows.isEmpty {
                Text("No environment variables")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.vertical, 4)
            } else {
                ForEach($rows) { $row in
                    HStack(spacing: 6) {
                        TextField("KEY", text: $row.key)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: row.key) { _ in flush() }

                        Text("=")
                            .foregroundColor(.secondary)

                        TextField("value", text: $row.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12, design: .monospaced))
                            .onChange(of: row.value) { _ in flush() }

                        Button {
                            remove(row.id)
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .help("Remove")
                    }
                }
            }

            Button {
                addRow()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus.circle.fill")
                    Text("Add Variable")
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .foregroundColor(.accentColor)
            .padding(.top, 2)
        }
        .onAppear(perform: syncFromBinding)
    }

    // MARK: - Mutations

    private func addRow() {
        rows.append(Row(key: "", value: ""))
    }

    private func remove(_ id: UUID) {
        rows.removeAll { $0.id == id }
        flush()
    }

    private func flush() {
        var dict: [String: String] = [:]
        for row in rows {
            let key = row.key
            guard !key.isEmpty else { continue }
            dict[key] = row.value
        }
        if dict != env {
            env = dict
        }
    }

    private func syncFromBinding() {
        // Only seed from the binding if we haven't populated rows yet.
        // This preserves editing order across view updates.
        guard rows.isEmpty else { return }
        rows = env
            .sorted { $0.key < $1.key }
            .map { Row(key: $0.key, value: $0.value) }
    }
}
