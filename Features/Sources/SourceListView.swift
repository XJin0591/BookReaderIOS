import SwiftUI

struct SourceListView: View {
    var body: some View {
        ContentUnavailableView("还没有书源", systemImage: "books.vertical", description: Text("导入 Legado 书源后，就能开始搜索。"))
            .navigationTitle("书源管理")
    }
}
