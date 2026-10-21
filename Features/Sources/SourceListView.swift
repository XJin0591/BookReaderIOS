import SwiftUI

struct SourceListView: View {
    @ObservedObject var model: AppModel
    @State private var showingImport = false
    @State private var sourceToDelete: BookSource?

    var body: some View {
        Group {
            if model.sources.isEmpty {
                ContentUnavailableView("还没有书源", systemImage: "books.vertical", description: Text("导入 Legado 书源后，就能开始搜索。"))
            } else {
                List {
                    ForEach(model.sources) { source in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(source.bookSourceName)
                                Text(source.bookSourceURL).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("启用", isOn: Binding(get: { source.enabled }, set: { model.setEnabled($0, sourceID: source.id) }))
                                .labelsHidden()
                                .accessibilityLabel("启用\(source.bookSourceName)")
                        }
                        .swipeActions {
                            Button(role: .destructive) { sourceToDelete = source } label: { Label("删除", systemImage: "trash") }
                            NavigationLink { SourceDebugView(source: source) } label: { Label("测试", systemImage: "checkmark.circle") }
                        }
                    }
                }
            }
        }
        .navigationTitle("书源管理")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { showingImport = true } label: { Label("导入", systemImage: "square.and.arrow.down") }
            }
        }
        .sheet(isPresented: $showingImport) { SourceImportView { model.importSources($0) } }
        .alert("删除书源？", isPresented: Binding(get: { sourceToDelete != nil }, set: { if !$0 { sourceToDelete = nil } })) {
            Button("取消", role: .cancel) { sourceToDelete = nil }
            Button("删除", role: .destructive) {
                if let sourceToDelete { model.delete(sourceID: sourceToDelete.id) }
                sourceToDelete = nil
            }
        } message: {
            Text(sourceToDelete?.bookSourceName ?? "")
        }
    }
}
