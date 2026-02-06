import SwiftUI

struct RepoAllowlistTokensView: View {
    @Binding var repos: [String]
    @State private var input: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Repo allowlist").font(.headline)
            Text("Restrict search to owner/repo entries. Overrides org selection.")
                .font(.caption)
                .foregroundStyle(.secondary)

            if repos.isEmpty {
                Text("No repos added").font(.caption).foregroundStyle(.secondary)
            } else {
                FlowLayout(items: repos) { repo in
                    HStack(spacing: 6) {
                        Text(repo).font(.caption)
                        Button {
                            repos.removeAll { $0 == repo }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.gray.opacity(0.15))
                    .clipShape(Capsule())
                }
            }

            HStack {
                TextField("owner/repo", text: $input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { addInput() }
                Button("Add") { addInput() }
                    .disabled(!isValidRepo(input))
            }
        }
    }

    private func addInput() {
        let parts = input
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { isValidRepo($0) }

        for repo in parts where !repos.contains(repo) {
            repos.append(repo)
        }
        input = ""
    }

    private func isValidRepo(_ value: String) -> Bool {
        let chunks = value.split(separator: "/")
        return chunks.count == 2 && !chunks[0].isEmpty && !chunks[1].isEmpty
    }
}

private struct FlowLayout<Data: Collection, Content: View>: View where Data.Element: Hashable {
    let items: Data
    let content: (Data.Element) -> Content

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(Array(items), id: \.self) { item in
                content(item)
            }
        }
    }
}
