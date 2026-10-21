import SwiftUI
import UniformTypeIdentifiers

struct SourceImportView: View {
    let onImport: ([BookSource]) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var subscriptionURL = ""
    @State private var showingFileImporter = false
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("粘贴书源 JSON") {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .accessibilityIdentifier("书源JSON输入")
                }
                Section("订阅 URL") {
                    TextField("https://example.com/sources.json", text: $subscriptionURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .accessibilityIdentifier("书源订阅URL输入")
                    Button {
                        importRemoteURL(subscriptionURL)
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("从 URL 导入")
                        }
                    }
                    .disabled(isImporting || subscriptionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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

    private func importRemoteURL(_ value: String) {
        isImporting = true
        errorMessage = nil
        Task {
            do {
                let sources = try await BookSourceRemoteImporter().importSources(from: value)
                onImport(sources)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
                isImporting = false
            }
        }
    }
}
