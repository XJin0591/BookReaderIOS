import SwiftUI
import UniformTypeIdentifiers

struct SourceImportView: View {
    let onImport: ([BookSource]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var showingFileImporter = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("粘贴书源 JSON") {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("书源JSON输入")
                }
                Section {
                    Button("选择 JSON 文件") { showingFileImporter = true }
                    Button("导入书源") { importText(text) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
            }
            .navigationTitle("导入书源")
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("取消") { dismiss() } } }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.json], allowsMultipleSelection: true) { result in
                switch result {
                case .success(let urls):
                    let contents = urls.compactMap { url -> String? in
                        let accessed = url.startAccessingSecurityScopedResource()
                        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                        return try? String(contentsOf: url, encoding: .utf8)
                    }
                    importText(contents.joined(separator: "\n"))
                case .failure(let error): errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func importText(_ value: String) {
        do {
            let sources = try BookSourceImport.decode(Data(value.utf8))
            onImport(sources)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
